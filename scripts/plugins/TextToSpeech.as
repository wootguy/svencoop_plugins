#include "HashMap"

// **************************************************
//
// ADD, REMOVE, AND REARRANGE VOICES HERE
// Format is: Voice(volume percentage, "folder name", "Display name"),
//
array<Voice> g_all_voices = 
{
	Voice(100, "morgan",  "Morgan Freeman"),
	Voice(100, "macho",   "\"Macho Man\" Randy Savage"),
	Voice(70, "portal",  "Portal Turret"),
	Voice(90, "moon", "Moonbase Alpha"),
	Voice(50,  "grunt",   "HL Grunt"),
	Voice(95,  "holo2",   "Hologram Assistant"),
	Voice(100, "w00tguy", "w00tguy"),
	Voice(100, "keen",    "Keen"),
	Voice(0,   "",        "None (disables speech)")
};

//
// **************************************************


class Voice
{
	string folder; // name of folder
	string name; // display name
	float volume; // default volume level
	
	Voice(int ivolume, string ifolder, string iname)
	{
		folder = ifolder;
		name = iname;
		if (ivolume < 0) ivolume = 0;
		if (ivolume > 100) ivolume = 100;
		volume = ivolume / 100.0f;
	}
	
	Voice() {}
}

class Phoneme
{
	string soundFile;  // path to the sound clip
	string code;       // how this sound appears as text ("ch", "aa")
	int pitch;
	float len; // length of the sound
	int stress; // stress value
	
	Phoneme() {
		pitch = 100;
		stress = 0;
	}
	
	Phoneme(string codetxt)
	{
		soundFile = codetxt;
		code = codetxt;
		pitch = 100;
		stress = 2;
		len = arpaLen(codetxt, stress);
		
		// don't bother with these subtley different phonemes
		if (codetxt == "ao") soundFile = "aa";
	}
	
	Phoneme(string codetxt, int istress)
	{
		soundFile = codetxt;
		code = codetxt;
		pitch = 100;
		stress = istress;
		len = arpaLen(codetxt, stress);
		
		// don't bother with this weird one. Who pronounces "ought" like oh-aa-t?
		if (codetxt == "ao") soundFile = "aa";
	}
	
	Phoneme(string codetxt, int ipitch, float flen)
	{		
		soundFile = codetxt;
		code = codetxt;
		pitch = ipitch;
		len = flen;
		stress = 2;
		
		// don't bother with these subtley different phonemes
		if (codetxt == "ao") soundFile = "aa";
	}
}

class PlayerState
{
	CTextMenu@ menu;
	int voice = 0;  // voice id this player is using
	int pitch = 100;	// voice pitch adjustment (100 = normal, range = 1-255)
	int channel = -1;
	float volume = 1.0f;
	array<CScheduledFunction@> speaking; // list of phonemes that are scheduled to be spoken
	float speakEnd; // time when speech will be over on channel
	
	void initMenu(CBasePlayer@ plr, TextMenuPlayerSlotCallback@ callback)
	{
		CTextMenu temp(@callback);
		@menu = @temp;
	}
	
	void openMenu(CBasePlayer@ plr) 
	{
		if ( menu.Register() == false ) {
			g_Game.AlertMessage( at_console, "Oh dear menu registration failed\n");
		}
		menu.Open(0, 0, plr);
	}
}

int default_voice = 0;

// All possible sound channels we can use
dictionary player_states; // persistent-ish player data, organized by steam-id or username if on a LAN server, values are @PlayerState
array<Phoneme@> g_all_phonemes; // for straight-forward precaching, duplicates the data in g_talkers
array<Phoneme@> g_all_phos_with_stress; // all possible combinations of phonemes and stress values
dictionary g_phonemes;
dictionary g_pho_to_idx;
dictionary g_idx_to_pho;
dictionary special_chars;
dictionary lettermap;
dictionary long_sounds;
dictionary voice_choices;
array<EHandle> players;
HashMapArrayUint8 english(131072);

// speakers will cycle through channels for each talk so we can play multiple voices at once
array<SOUND_CHANNEL> g_channels = {CHAN_STATIC, CHAN_VOICE, CHAN_STREAM};

void print(string text) { g_Game.AlertMessage( at_console, "tts: " + text); }
void println(string text) { print(text + "\n"); }
void printSuccess() { g_Game.AlertMessage( at_console, "SUCCESS\n"); }

CCVar@ g_disabled;
CCVar@ g_spam_length;
CCVar@ g_spam_delay;

void PluginInit()
{
	g_Module.ScriptInfo.SetAuthor( "w00tguy" );
	g_Module.ScriptInfo.SetContactInfo( "w00tguy123 - forums.svencoop.com" );
	g_Hooks.RegisterHook( Hooks::Player::ClientSay, @ClientSay );	
	g_Hooks.RegisterHook( Hooks::Game::MapChange, @MapChange );
	g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientJoin );

	loadLetterMap();
	loadPhonemes();
	loadMisc();
	loadEnglishWords();
	
	g_Scheduler.SetTimeout("FetchBotChat", 0.0);
	
	@g_disabled = CCVar("disabled", 0, "Disables speech for all users", ConCommandFlag::AdminOnly);
	@g_spam_length = CCVar("spam_length", 0, "Length in seconds before message is considered spam and cancelled", ConCommandFlag::AdminOnly);
	@g_spam_delay = CCVar("spam_delay", 0, "Time in seconds before a user is allowed to speak another message", ConCommandFlag::AdminOnly);
}

void MapInit()
{
	g_Game.AlertMessage( at_console, "Precaching " + g_all_phonemes.length() + " sounds\n");
	
	for (uint k = 0; k < g_all_voices.length(); k++)
	{
		if (g_all_voices[k].folder == "")
			continue;
		for (uint i = 0; i < g_all_phonemes.length(); i++) 
		{
			string snd = "texttospeech/" + g_all_voices[k].folder + "/" + g_all_phonemes[i].soundFile + ".ogg";
			g_SoundSystem.PrecacheSound(snd);
			g_Game.PrecacheGeneric("sound/" + snd);
		}
	}
	
}

HookReturnCode MapChange()
{
	// set all menus to null. Apparently this fixes crashes for some people:
	// http://forums.svencoop.com/showthread.php/43310-Need-help-with-text-menu#post515087
	array<string>@ stateKeys = player_states.getKeys();
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		if (state.menu !is null)
			@state.menu = null;
	}
	return HOOK_CONTINUE;
}

enum parse_mode {
	PARSE_SETTINGS,
	PARSE_VOICES,
	PARSE_CMDS_1,
	PARSE_CMDS_2,
	PARSE_SPECIAL_CMDS,
}

// converts single char to arpa phoneme
void loadLetterMap() {
	lettermap['a'] = 'aa';
	lettermap['b'] = 'b';
	lettermap['c'] = 'k';
	lettermap['d'] = 'd';
	lettermap['e'] = 'eh';
	lettermap['f'] = 'f';
	lettermap['g'] = 'g';
	lettermap['h'] = 'hh';
	lettermap['i'] = 'iy';
	lettermap['j'] = 'jh';
	lettermap['k'] = 'k';
	lettermap['l'] = 'l';
	lettermap['m'] = 'm';
	lettermap['n'] = 'n';
	lettermap['o'] = 'ow';
	lettermap['p'] = 'p';
	lettermap['q'] = 'k';
	lettermap['r'] = 'r';
	lettermap['s'] = 's';
	lettermap['t'] = 't';
	lettermap['u'] = 'uw';
	lettermap['v'] = 'v';
	lettermap['w'] = 'w';
	lettermap['x'] = 's';
	lettermap['y'] = 'y';
	lettermap['z'] = 'z';
	
	// combos
	lettermap['ch'] = 'ch';
	lettermap['ah'] = 'ae';
	lettermap['ae'] = 'ae';
	lettermap['uh'] = 'ah';
	lettermap['ow'] = 'aw';
	lettermap['ai'] = 'ay';
	lettermap['th'] = 'th';
	lettermap['er'] = 'er';
	lettermap['ee'] = 'ey';
	lettermap['ih'] = 'ih';
	lettermap['ih'] = 'ih';
	lettermap['oy'] = 'oy';
	lettermap['oo'] = 'uw';
	lettermap['ll'] = 'l';
}

int errs = 0;
int totalWords = 0;
bool halfwayLoaded = false;
bool startedLoad = false;

// I tried saving to a ByteBuffer but decoding took ages, and loading bytes wasn't any faster
void loadEnglishWords(File@ f=null)
{
	// http://www.speech.cs.cmu.edu/cgi-bin/cmudict
	
	if (f is null) {
		string dataPath = "scripts/plugins/cfg/cmudict-0.7b.txt";
		@f = g_FileSystem.OpenFile( dataPath, OpenFile::READ );
	}
	
	if (!startedLoad)
	{
		updatePlayerList();
		if (players.length() > 0 and players[0])
		{
			CBaseEntity@ ent = players[0];
			CBasePlayer@ plr = cast<CBasePlayer@>(ent);
			g_PlayerFuncs.SayText(plr, "Text to speech dictionary is loading...\n");
		}
		startedLoad = true;
	}
	
	int linesRead = 0;
	
	if( f !is null && f.IsOpen() )
	{
		string line;
		while( !f.EOFReached() )
		{
			f.ReadLine( line );
			
			if (line.Length() == 0 || line[0] == ';') {
				continue;
			}
			
			string word = line.SubString(0, line.FindFirstOf(" "));
			array<string> phos = line.SubString(line.Find(" ") + 1).Split(" ");
			
			array<uint8> pronounce;
			for (uint i = 0; i < phos.length(); i++) 
			{
				uint8 val = 0;
				if (!g_pho_to_idx.exists(phos[i]))
				{
					println("Invalid pho: " + phos[i]);
				}
				g_pho_to_idx.get(phos[i], val);
				pronounce.insertLast(val);
			}
			
			english.put(word, pronounce);
			totalWords++;
			
			if (linesRead++ > 32) {
				g_Scheduler.SetTimeout("loadEnglishWords", 0, @f);
				return;
			}
		}
	}
	
	//println("TOTAL WORDS: " + totalWords);
	//english.stats();
	
	updatePlayerList();
	if (players.length() > 0 and players[0])
	{
		CBaseEntity@ ent = players[0];
		CBasePlayer@ plr = cast<CBasePlayer@>(ent);
		g_PlayerFuncs.SayText(plr, "Text to speech dictionary is 100% loaded.\n");
	}
}

void loadMisc()
{
	special_chars['0'] = 'zero';
	special_chars['1'] = 'one';
	special_chars['2'] = 'two';
	special_chars['3'] = 'three';
	special_chars['4'] = 'four';
	special_chars['5'] = 'five';
	special_chars['6'] = 'six';
	special_chars['7'] = 'seven';
	special_chars['8'] = 'eight';
	special_chars['9'] = 'nine';
	special_chars['~'] = 'tilde'; // not in dict!
	special_chars['`'] = 'back quote';
	special_chars['!'] = 'exclamation point';
	special_chars['@'] = 'at';
	special_chars['#'] = 'hashtag';
	special_chars['$'] = 'dollar';
	special_chars['%'] = 'percent';
	special_chars['^'] = 'caret';
	special_chars['&'] = 'and';
	special_chars['*'] = 'asterisk';
	special_chars['('] = 'open paren';
	special_chars[')'] = 'close paren';
	special_chars['-'] = 'minus';
	special_chars['='] = 'equals';
	special_chars['_'] = 'underscore';
	special_chars['+'] = 'plus';
	special_chars['['] = 'open bracket';
	special_chars[']'] = 'close bracket';
	special_chars['\\'] = 'back slash';
	special_chars['{'] = 'open brace';
	special_chars['}'] = 'close brace';
	special_chars['|'] = 'pipe';
	special_chars[';'] = 'semicolon';
	special_chars['\''] = 'apostrophe';
	special_chars[':'] = 'colon';
	special_chars['"'] = 'quote';
	special_chars[','] = 'comma';
	special_chars['.'] = 'dot';
	special_chars['/'] = 'forward slash';
	special_chars['<'] = 'open bracket';
	special_chars['>'] = 'close bracket';
	special_chars['?'] = 'question mark';
	
	long_sounds['aa'] = 1;
	long_sounds['ae'] = 1;
	long_sounds['ah'] = 1;
	long_sounds['ao'] = 1;
	long_sounds['aw'] = 1;
	long_sounds['ay'] = 1;
	long_sounds['eh'] = 1;
	long_sounds['er'] = 1;
	long_sounds['ey'] = 1;
	long_sounds['ih'] = 1;
	long_sounds['iy'] = 1;
	long_sounds['m'] = 1;
	long_sounds['n'] = 1;
	long_sounds['ng'] = 1;
	long_sounds['ow'] = 1;
	long_sounds['oy'] = 1;
	long_sounds['r'] = 1;
	long_sounds['uh'] = 1;
	long_sounds['uw'] = 1;
}

void loadPhonemes()
{
	g_all_phonemes.insertLast(Phoneme("aa"));
	g_all_phonemes.insertLast(Phoneme("ae"));
	g_all_phonemes.insertLast(Phoneme("ah"));
	g_all_phonemes.insertLast(Phoneme("ao"));
	g_all_phonemes.insertLast(Phoneme("aw"));
	g_all_phonemes.insertLast(Phoneme("ay"));
	g_all_phonemes.insertLast(Phoneme("b"));
	g_all_phonemes.insertLast(Phoneme("ch"));
	g_all_phonemes.insertLast(Phoneme("d"));
	g_all_phonemes.insertLast(Phoneme("dh"));
	g_all_phonemes.insertLast(Phoneme("eh"));
	g_all_phonemes.insertLast(Phoneme("er"));
	g_all_phonemes.insertLast(Phoneme("ey"));
	g_all_phonemes.insertLast(Phoneme("f"));
	g_all_phonemes.insertLast(Phoneme("g"));
	g_all_phonemes.insertLast(Phoneme("hh"));
	g_all_phonemes.insertLast(Phoneme("ih"));
	g_all_phonemes.insertLast(Phoneme("iy"));
	g_all_phonemes.insertLast(Phoneme("jh"));
	g_all_phonemes.insertLast(Phoneme("k"));
	g_all_phonemes.insertLast(Phoneme("l"));
	g_all_phonemes.insertLast(Phoneme("m"));
	g_all_phonemes.insertLast(Phoneme("n"));
	g_all_phonemes.insertLast(Phoneme("ng"));
	g_all_phonemes.insertLast(Phoneme("ow"));
	g_all_phonemes.insertLast(Phoneme("oy"));
	g_all_phonemes.insertLast(Phoneme("p"));
	g_all_phonemes.insertLast(Phoneme("r"));
	g_all_phonemes.insertLast(Phoneme("s"));
	g_all_phonemes.insertLast(Phoneme("sh"));
	g_all_phonemes.insertLast(Phoneme("t"));
	g_all_phonemes.insertLast(Phoneme("th"));
	g_all_phonemes.insertLast(Phoneme("uh"));
	g_all_phonemes.insertLast(Phoneme("uw"));
	g_all_phonemes.insertLast(Phoneme("v"));
	g_all_phonemes.insertLast(Phoneme("w"));
	g_all_phonemes.insertLast(Phoneme("y"));
	g_all_phonemes.insertLast(Phoneme("z"));
	g_all_phonemes.insertLast(Phoneme("zh"));
	
	for (uint stress = 0; stress < 3; stress++)
	{
		for (uint k = 0; k < g_all_phonemes.size(); k++)
		{
			string sval = g_all_phonemes[k].code + stress;
			uint datValue = k + (stress << 6);
			Phoneme pho(g_all_phonemes[k].code, stress);
			g_all_phos_with_stress.insertLast(pho);
			g_idx_to_pho[datValue] = pho;
			
			g_pho_to_idx[sval.ToUppercase()] = datValue;
			if (stress == 0)
			{
				sval = g_all_phonemes[k].code;
				g_pho_to_idx[sval.ToUppercase()] = datValue;
			}
		}
	}
}

void updatePlayerList()
{
	players.resize(0);
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByClassname(ent, "player"); 
		if (ent !is null)
		{
			EHandle e = ent;
			players.insertLast(e);
		}
	} while (ent !is null);
}

void playSoundDelay(Phoneme@ pho, Voice@ voice, int channelIdx) {
	// play for all players, but on a single channel so phonemes don't overlap
	for (uint i = 0; i < players.length(); i++)
	{
		if (players[i])
		{
			CBaseEntity@ plr = players[i];
			PlayerState@ state = getPlayerState(cast<CBasePlayer@>(plr));
			if (state.volume > 0)
			{
				string file = "texttospeech/" + voice.folder + "/" + pho.soundFile + ".ogg";
				g_SoundSystem.PlaySound(plr.edict(), g_channels[channelIdx], file, state.volume*voice.volume, ATTN_NONE, 0, pho.pitch, plr.entindex());
			}
		}
	}	
}

float arpaLen(string c, int stress)
{
	if (c == "l") return 0.15f;
	if (c == "b") return 0.05f;
	if (c == "g") return 0.06f;
	if (c == "dh") return 0.075f;
	if (c == "jh") return 0.15f;
	if (c == "d") return 0.1f;
	if (c.Length() == 1 || c == "hh" || c == "th") return 0.08f;
	
	if (stress == 2) // secondary stress (slightly more than 0 stress)
		return 0.15f;
	if (stress == 1) // primary stress (considerably more stress)
		return 0.25f;
	return 0.13f;
}

// converts a long number to words
array<string> convertLongNumber(string longnum)
{
	array<string> words;
	
	bool isDollars = longnum.Find("$") != uint(-1);
	bool isNegative = longnum.Find("-") != uint(-1);
	
	if (isNegative)
	{
		words.insertLast("negative");
	}
	
	string whole = "";
	string fraction = "";
	bool gotDot = false;
	for (uint i = 0; i < longnum.Length(); i++)
	{
		if (longnum[i] == "," || longnum[i] == "$" || longnum[i] == '-')
			continue;
			
		if (longnum[i] == ".")
		{
			gotDot = true;
			continue;
		}
			
		if (gotDot)
			fraction += longnum[i];
		else
			whole += longnum[i];
	}
	
	if (whole.Length() > 0)
	{
		array<string> parts;
		
		uint fullNum = atoi(whole);
		while(true)
		{
			if (whole.Length() > 3)
			{
				parts.insertLast(whole.SubString(whole.Length() - 3));
				whole = whole.SubString(0, whole.Length() - 3);
			}
			else
			{
				parts.insertLast(whole);
				break;
			}
		}

		for (int i = int(parts.length())-1; i >= 0; i--)
		{				
			string snum = parts[i];
			int num = atoi(parts[i]);
			
			string word;
			if (num >= 100)
			{
				special_chars.get(string(snum[0]), word);
				words.insertLast(word);
				words.insertLast("hundred");
				num = num % 100;
				if (num > 0)
					words.insertLast("and");
			}
			if (num < 20)
			{
				if (num >= 10)
				{
					if (num == 10) words.insertLast("ten");
					if (num == 11) words.insertLast("eleven");
					if (num == 12) words.insertLast("twelve");
					if (num == 13) words.insertLast("thirteen");
					if (num == 14) words.insertLast("fourteen");
					if (num == 15) words.insertLast("fifteen");
					if (num == 16) words.insertLast("sixteen");
					if (num == 17) words.insertLast("seventeen");
					if (num == 18) words.insertLast("eighteen");
					if (num == 19) words.insertLast("nineteen");
					num = 0;
				}
			}
			else
			{
				if (num >= 90) words.insertLast("ninety");
				else if (num >= 80) words.insertLast("eighty");
				else if (num >= 70) words.insertLast("seventy");
				else if (num >= 60) words.insertLast("sixty");
				else if (num >= 50) words.insertLast("fifty");
				else if (num >= 40) words.insertLast("forty");
				else if (num >= 30) words.insertLast("thirty");
				else if (num >= 20) words.insertLast("twenty");
					
				num = num % 10;
			}
			
			if (num > 0)
			{
				special_chars.get(string(snum[snum.Length()-1]), word);
				words.insertLast(word);
			}

			if (i == 1) words.insertLast("thousand");
			if (i == 2) words.insertLast("million");
			if (i == 3) words.insertLast("billion");
			if (i == 4) words.insertLast("trillion");
			if (i == 5) words.insertLast("quadrillion");
			if (i == 6) words.insertLast("quintillion");
			if (i == 7) words.insertLast("sextillion");
			if (i == 8) words.insertLast("septillion");
			if (i == 9) words.insertLast("octillion");
			if (i == 10) words.insertLast("nonillion");
			if (i == 11) words.insertLast("decillion");
			if (i == 12) words.insertLast("undecillion");
			if (i == 13) words.insertLast("duodecillion");
			if (i == 14) words.insertLast("tredecillion");
			if (i == 15) words.insertLast("quattuordecillion");
			if (i == 16) words.insertLast("quindecillion");
			if (i == 17) words.insertLast("sexdecillion");
			if (i == 18) words.insertLast("septendecillion");
			if (i == 19) words.insertLast("octodecillion");
			if (i == 20) words.insertLast("novemdecillion ");
			if (i == 21) words.insertLast("vigintillion");
			if (i == 22) words.insertLast("centillion");
			if (i >= 23) words.insertLast("something");
		}
		
		if (fullNum == 0)
			words.insertLast("zero");
	}
	
	if (fraction.Length() > 0)
	{
		words.insertLast("point");
		
		for (uint i = 0; i < fraction.Length(); i++)
		{
			string word;
			special_chars.get(string(fraction[i]), word);
			words.insertLast(word);
		}
	}
	
	if (isDollars)
	{
		words.insertLast("you");
		words.insertLast("s");
		words.insertLast("dollars");
	}
	
	return words;
}

// break a word down into phonemes
array<Phoneme> getPhonemes(string word)
{
	array<Phoneme> phos;
	
	word = word.ToUppercase();
	if (english.exists(word)) 
	{
		array<uint8> phoValues = english.get(word);
		for (uint i = 0; i < phoValues.size(); i++)
		{
			Phoneme p = cast<Phoneme>(g_idx_to_pho[phoValues[i]]);
			phos.insertLast(p);
		}
	} 
	else 
	{   
		// freestyle it
		for (uint i = 0; i < word.Length(); i++)
		{
			string letter = string(word[i]).ToLowercase();
			string next = "";
			if (i < word.Length() - 1)
				next = string(word[i+1]).ToLowercase();
				
			string val;
			if (lettermap.exists(letter + next))
			{
				lettermap.get(letter + next, val);
				array<string> ps = val.Split(" ");
				
				for (uint k = 0; k < ps.length(); k++)
					phos.insertLast(Phoneme(ps[k]));
					
				i++;
			}
			else if (lettermap.exists(letter)) 
			{
				lettermap.get(letter, val);			
				phos.insertLast(Phoneme(val));
			} else {
				println("NO LETTER FOR: " + letter);
			}
		}
	}

	return phos;
}


// pick the least saturated one
int getBestChannel()
{
	array<string>@ stateKeys = player_states.getKeys();	
	array<int> channelUsage(g_channels.length());
	for (uint i = 0; i < g_channels.length(); i++)
		channelUsage[i] = 0;
	
	for (uint i = 0; i < stateKeys.length(); i++)
	{
		PlayerState@ state = cast<PlayerState@>( player_states[stateKeys[i]] );
		if (state.channel >= 0 and state.channel < int(g_channels.length()))
			if (state.speakEnd > g_Engine.time)
				channelUsage[state.channel]++;
	}
	
	int bestChannel = 0;
	int leastUsage = 32;
	for (uint i = 0; i < channelUsage.length(); i++)
	{
		if (channelUsage[i] < leastUsage)
		{
			bestChannel = i;
			leastUsage = channelUsage[i];
		}
	}
	
	//println("BEST CHANNEL: " + bestChannel + " USAGE: " + leastUsage);
	return bestChannel;
}

// where the magic happens
void doSpeech(CBasePlayer@ plr, array<string> args)
{	
	bool shout = false;
	bool ask = false;
	
	PlayerState@ state = getPlayerState(plr);
	
	if (g_disabled.GetBool() or g_all_voices[state.voice].folder == "") // Chose "None" voice (disables text to speech)
		return;
		
	if (g_spam_delay.GetFloat() > 0 and g_Engine.time < state.speakEnd + g_spam_delay.GetFloat())
		return; // not enough time passed between messages
	
	state.channel = -1; // ignore self in getBestChannel
	state.channel = getBestChannel();
	
	updatePlayerList();
	
	if (state.speaking.length() > 0)
	{
		for (uint i = 0; i < state.speaking.length(); i++)
			g_Scheduler.RemoveTimer(state.speaking[i]);
		state.speaking.resize(0);
	}
	
	array<string> words;
	for (uint i = 0; i < args.size(); i++)
	{
		string word = args[i];
		int inum = 0;
		while ( (inum = word.FindFirstOf("0123456789!@#$%^&*()-=_+[]{};':\",./<>?\\|`~")) != -1) 
		{
			string special = word[inum];
			bool isLongNumber = false;
			
			if (special.FindFirstOf("0123456789.,$-") == 0 and (word.Length() - inum) > 1) // part of a number?
			{
				string next = word.SubString(inum+1);
				while (next.FindFirstOf("0123456789.,$-") == 0)
				{
					if (next.FindFirstOf("0123456789") == 0)
						isLongNumber = true;
					special += next[0];
					if (next.Length() == 1)
						break;
					next = next.SubString(1);
				}
				if (!isLongNumber)
					special = word[inum];
			}
			
			string newWord;
			if (inum > 0)
				words.insertLast(word.SubString(0, inum));	
			
			if (isLongNumber)
			{
				array<string> sp = convertLongNumber(special);
				for (uint k = 0; k < sp.length(); k++)
					words.insertLast(sp[k]);
				
			}
			else if (special_chars.exists(special))
			{
				// interpret dots at the end of a word as pauses
				bool dotdotdot = true;
				if (word[inum] == '.')
				{
					for (uint k = inum+1; k < word.Length(); k++)
					{
						if (word[k] != '.')
						{
							dotdotdot = false;
							break;
						}
					}
				}
				else
					dotdotdot = false;
				
				if (dotdotdot or (word.FindFirstOf("!,.?'") == word.Length()-1 and inum == int(word.Length()-1))) // just punctuation?
				{
					if (special == "," || special == ".")
						words.insertLast(".");
					if (special == "!")
						shout = true;
					if (special == "?")
						ask = true;
				}
				else
				{
					string special_words;
					special_chars.get(special, special_words);
					array<string> sp = special_words.Split(" ");
					for (uint k = 0; k < sp.length(); k++)
						words.insertLast(sp[k]);
				}
			}
			
			if (word.Length() - uint(inum) == special.Length())
			{
				word = "";
				break;
			}
			word = word.SubString(inum+special.Length());
		}
		
		if (word.Length() > 0)
			words.insertLast(word);
	}
	
	// convert words to phonemes
	array<Phoneme> all_phos;
	int totalVowels = 0;
	for (uint i = 0; i < words.length(); i++)
	{
		string word = words[i];
		
		array<Phoneme> phos = getPhonemes(word);
		
		for (uint k = 0; k < phos.length(); k++) {
			all_phos.insertLast(phos[k]);
			if (long_sounds.exists(phos[k].code))
				totalVowels++;
		}
		
		all_phos.insertLast(Phoneme(" "));
	}
	
	bool all_consonants = false;
	if (totalVowels == 0)
	{
		totalVowels = all_phos.length();
		all_consonants = true; // still want to do intonation changes tho
	}
	float vol = 1.0f;
	float delay = 0;
	int pitch = state.pitch;
	if (shout or ask)
		pitch += 5;
	uint v = 0;
	
	// speak the phonemes
	for (uint i = 0; i < all_phos.length(); i++) {
		Phoneme@ pho = all_phos[i];
		
		if (long_sounds.exists(pho.code) || all_consonants)
		{
			if (ask)
			{
				uint lower = 1;
				uint steady = 2;
				uint lower2 = totalVowels - 1;
				if (v >= lower2)
					pitch -= 5;
				else if (v >= lower and v < steady)
					pitch -= 5;
			}
			if (shout)
			{
				uint lower = 0;
				uint rise = totalVowels / 3;
				if (v >= rise)
					pitch += 5;
				else if (v >= lower)
					pitch -= 5;
			}
			v++;
		}
		
		pho.pitch = pitch;
		
		if (pho.pitch < 30)
			pho.pitch = 30;
		else if (pho.pitch > 255)
			pho.pitch = 255;
		
		//println("SPEAK: " + pho.soundFile + " " + pho.stress);
		
		if (pho.code == ".")
			delay += 0.2f;
		else if (pho.code == " ") {
			delay += 0.1f;
		} else {
			state.speaking.insertLast( g_Scheduler.SetTimeout("playSoundDelay", delay, @pho, @g_all_voices[state.voice], state.channel) );
			delay += pho.len;
			
			if (g_spam_length.GetFloat() > 0 and delay > g_spam_length.GetFloat())
				break; // just stop here. It's a spam message.
		}
	}
	
	state.speakEnd = g_Engine.time + delay;
	
	// let bots know when they can talk again without overlapping
	if (g_bot_chat_ent)
	{
		CBaseEntity@ chat = g_bot_chat_ent;
		if (chat.pev.fuser1 < state.speakEnd)
		{
			chat.pev.fuser1 = state.speakEnd;
		}
	}
}


// Will create a new state if the requested one does not exit
PlayerState@ getPlayerState(CBasePlayer@ plr)
{	
	string steamId = g_EngineFuncs.GetPlayerAuthId( plr.edict() );
	if (steamId == 'STEAM_ID_LAN' or steamId == 'BOT') {
		steamId = plr.pev.netname;
	}
	
	if ( !player_states.exists(steamId) )
	{
		PlayerState state;
		state.voice = default_voice;
		state.pitch = 100;
		state.volume = 1.0f;
		state.speakEnd = 0;
		player_states[steamId] = state;
	}
	return cast<PlayerState@>( player_states[steamId] );
}

void voiceMenuCallback(CTextMenu@ menu, CBasePlayer@ plr, int page, const CTextMenuItem@ item)
{
	if (item is null)
		return; // selected "Exit"
	PlayerState@ state = getPlayerState(plr);
	
	string choice;
	item.m_pUserData.retrieve(choice);
	state.voice = atoi(choice);
	
	g_PlayerFuncs.SayText(plr, "Your text-to-speech voice was set to " + g_all_voices[state.voice].name + "\n");
}

array<string> argsToArray( const CCommand@ args)
{
	array<string> new_args;
	for (int i = 0; i < args.ArgC(); i++)
		new_args.insertLast(args[i]);
	return new_args;
}

EHandle g_bot_chat_ent;
int lastChatIdx = -1;
void FetchBotChat()
{
	if (g_bot_chat_ent)
	{
		CBaseEntity@ chat = g_bot_chat_ent;
		if (chat.pev.iuser1 != lastChatIdx)
		{
			lastChatIdx = chat.pev.iuser1;
			
			edict_t@ e_plr = @g_EngineFuncs.PEntityOfEntIndex(chat.pev.iuser2);
			CBasePlayer@ plr =  cast<CBasePlayer@>(g_EntityFuncs.Instance(e_plr));
			if (plr !is null)
			{
				string cmd = chat.pev.message;
				array<string> split_args = cmd.Split(" ");
				array<string> args;
				for (uint i = 0; i < split_args.size(); i++)
					if (split_args[i].Length() > 0)
						args.insertLast(split_args[i]);
				if (args.length() > 0)
					HandleBotChat(plr, args);
			}
		}
		g_Scheduler.SetTimeout("FetchBotChat", 0.0);
	}
	else
	{
		g_bot_chat_ent = @g_EntityFuncs.FindEntityByTargetname(null, "w00tbot_chat"); 
		g_Scheduler.SetTimeout("FetchBotChat", 1.0);
	}
}

void HandleBotChat(CBasePlayer@ plr, array<string> args)
{
	if (doCommand(plr, args))
		return;
	doSpeech(plr, args);
}

bool doCommand(CBasePlayer@ plr, array<string> args)
{
	PlayerState@ state = getPlayerState(plr);
	
	if ( args.size() > 0 )
	{
		if ( args[0] == ".tts" )
		{
			if (g_disabled.GetBool())
			{
				g_PlayerFuncs.SayText(plr, 'Text to speech is currently disabled.\n');
				return true;
			}
			
			if (args.size() > 1)
			{
				if (args[1] == "pitch" and args.size() > 2)
				{
					int pitch = atoi(args[2]);
					state.pitch = pitch;
					g_PlayerFuncs.SayText(plr, "Your text-to-speech voice pitch was set to " + pitch + "\n");
					return true;
				}
				else if (args[1] == "vol" and args.size() > 2)
				{
					int vol = atoi(args[2]);
					if (vol < 0) vol = 0;
					if (vol > 100) vol = 100;
					state.volume = vol / 100.0f;
					g_PlayerFuncs.SayText(plr, "Text-to-speech volume set to " + vol + "%\n");
					return true;
				}
				else if (args[1] == "voice")
				{
					if (args.size() > 2)
					{
						for (uint k = 0; k < g_all_voices.length(); k++)
						{
							if (int(g_all_voices[k].name.ToLowercase().Find(args[2])) != -1)
							{
								state.voice = k;
								g_PlayerFuncs.SayText(plr, "Your text-to-speech voice was set to " + g_all_voices[k].name + "\n");
								break;
							}
						}
					}
					else
					{
						state.initMenu(plr, voiceMenuCallback);
						state.menu.SetTitle("Voice selection:\n");
						
						for (uint k = 0; k < g_all_voices.length(); k++)
							state.menu.AddItem(g_all_voices[k].name, any(string(k)));
						state.openMenu(plr);
					}
					
					return true;
				}
			}
			else
			{
				g_PlayerFuncs.SayText(plr, "Text to speech commands:\n");
				g_PlayerFuncs.SayText(plr, 'Say ".tts pitch X" to change your voice pitch (where X = 1-255).\n');
				g_PlayerFuncs.SayText(plr, 'Say ".tts voice" to select a different voice.\n');
				g_PlayerFuncs.SayText(plr, 'Say ".tts vol X" to adjust global speech volume (where X = 0-100).\n');
				if (g_spam_length.GetFloat() > 0 or g_spam_delay.GetFloat() > 0)
					g_PlayerFuncs.SayText(plr, 'TTS anti-spam is enabled (Length ' + g_spam_length.GetFloat() + ', Delay ' + g_spam_delay.GetFloat() + ').\n');
				else
					g_PlayerFuncs.SayText(plr, 'TTS anti-spam is disabled.\n');
			}

			
			return true;
		}
	}
	return false;
}

HookReturnCode ClientSay( SayParameters@ pParams )
{	
	CBasePlayer@ plr = pParams.GetPlayer();
	const CCommand@ args = pParams.GetArguments();
	
	if (doCommand(plr, argsToArray(args)))
	{
		pParams.ShouldHide = true;
		return HOOK_HANDLED;
	}
	else {		
		doSpeech(plr, argsToArray(args));
	}
	
	return HOOK_CONTINUE;
}

HookReturnCode ClientJoin(CBasePlayer@ plr) 
{
	updatePlayerList();
	return HOOK_CONTINUE;
}

CClientCommand _tts("tts", "Text to speech settings", @voiceCmd );

void voiceCmd( const CCommand@ args )
{
	CBasePlayer@ plr = g_ConCommandSystem.GetCurrentPlayer();
	doCommand(plr, argsToArray(args));
}
