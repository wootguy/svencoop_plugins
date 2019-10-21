/*
Copyright (c) 2017 Drake "MrOats" Denston

This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.
*/

/*
Current Status: Stable, report bugs on forums.
Documentation: https://github.com/MrOats/AngelScript_SC_Plugins/wiki/RockTheVote.as
*/

final class RTV_Data
{

  private string m_szVotedMap = "";
  private string m_szNominatedMap = "";
  private bool m_bHasRTV = false;
  private CBasePlayer@ m_pPlayer;
  private string m_szPlayerName;
  private string m_szSteamID = "";

  //RTV Data Properties

  string szVotedMap
  {
    get const { return m_szVotedMap; }
    set { m_szVotedMap = value; }
  }
  string szNominatedMap
  {
    get const { return m_szNominatedMap; }
    set { m_szNominatedMap = value; }
  }
  bool bHasRTV
  {
    get const { return m_bHasRTV; }
    set { m_bHasRTV = value; }
  }
  CBasePlayer@ pPlayer
  {
    get const { return m_pPlayer; }
    set { @m_pPlayer = value; }
  }
  string szSteamID
  {
    get const { return m_szSteamID; }
    set { m_szSteamID = value; }
  }
  string szPlayerName
  {
    get const { return m_szPlayerName; }
    set { m_szPlayerName = value; }
  }


  //RTV Data Functions


  //Constructor

  RTV_Data(CBasePlayer@ pPlr)
  {

    @pPlayer = pPlr;
    szSteamID = g_EngineFuncs.GetPlayerAuthId( pPlayer.edict() );
    szPlayerName = pPlayer.pev.netname;

  }

}

final class PCG
{

  private uint64 m_iseed;

  string seed
  {
    get const { return m_iseed; }
  }

  //PCG Functions

  uint nextInt(uint upper)
  {

    uint threshold = -upper % upper;

    while (true)
    {

      uint r =  nextInt();

      if (r >= threshold)
        return r % upper;

    }

    return upper;

  }


  uint nextInt()
  {
    uint64 oldstate = m_iseed;
    m_iseed = oldstate * uint64(6364136223846793005) + uint(0);
    uint xorshifted = ((oldstate >> uint(18)) ^ oldstate) >> uint(27);
    uint rot = oldstate >> uint(59);
    return (xorshifted >> rot) | (xorshifted << ((-rot) & 31));
  }

  //PCG Constructors

  PCG(uint64 in_seed)
  {

    m_iseed = in_seed;

  }

  //Default Constructor
  PCG()
  {

    m_iseed = UnixTimestamp();

  }

}

//ClientCommands

CClientCommand forcertv("forcertv", "Lets admin force a vote", @ForceVote, ConCommandFlag::AdminOnly);
CClientCommand addnom("addnom", "Lets admin add as many nominatable maps as possible", @AddNominateMap, ConCommandFlag::AdminOnly);
CClientCommand removenom("removenom", "Lets admin add as many nominatable maps as possible", @RemoveNominateMap, ConCommandFlag::AdminOnly);
CClientCommand cancelrtv("cancelrtv", "Lets admin cancel an ongoing RTV vote", @CancelVote, ConCommandFlag::AdminOnly);

//Global Vars

CTextMenu@ rtvmenu = null;
CTextMenu@ nommenu = null;

array<RTV_Data@> rtv_plr_data;
array<string> forcenommaps;
array<string> prevmaps;
array<string> maplist;

PCG pcg_gen = PCG();

bool isVoting = false;
bool canRTV = false;

int secondsleftforvote = 0;

CCVar@ g_SecondsUntilVote;
CCVar@ g_MapList;
CCVar@ g_WhenToChange;
CCVar@ g_MaxMapsToVote;
CCVar@ g_VotingPeriodTime;
CCVar@ g_PercentageRequired;
CCVar@ g_ChooseEnding;
CCVar@ g_ExcludePrevMaps;
CCVar@ g_PlaySounds;

//Global Timers/Schedulers

CScheduledFunction@ g_TimeToVote = null;
CScheduledFunction@ g_TimeUntilVote = null;

//Hooks

void PluginInit()
{

  g_Module.ScriptInfo.SetAuthor("MrOats (w/ modifications by incognico)");
  g_Module.ScriptInfo.SetContactInfo("http://forums.svencoop.com/showthread.php/44609-Plugin-RockTheVote");
  g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @DisconnectCleanUp);
  g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @AddPlayer);
  g_Hooks.RegisterHook(Hooks::Game::MapChange, @ResetVars);
  g_Hooks.RegisterHook(Hooks::Player::ClientSay, @Decider);

  @g_SecondsUntilVote = CCVar("secondsUntilVote", 120, "Delay before players can RTV after map has started", ConCommandFlag::AdminOnly);
  @g_MapList = CCVar("szMapListPath", "mapcycle.txt", "Path to list of maps to use. Defaulted to map cycle file", ConCommandFlag::AdminOnly);
  @g_WhenToChange = CCVar("iChangeWhen", 0, "When to change maps post-vote: <0 for end of map, 0 for immediate change, >0 for seconds until change", ConCommandFlag::AdminOnly);
  @g_MaxMapsToVote = CCVar("iMaxMaps", 9, "How many maps can players nominate and vote for later", ConCommandFlag::AdminOnly);
  @g_VotingPeriodTime = CCVar("secondsToVote", 25, "How long can players vote for a map before a map is chosen", ConCommandFlag::AdminOnly);
  @g_PercentageRequired = CCVar("iPercentReq", 66, "0-100, percent of players required to RTV before voting happens", ConCommandFlag::AdminOnly);
  @g_ChooseEnding = CCVar("iChooseEnding", 1, "Set to 1 to revote when a tie happens, 2 to choose randomly amongst the ties, 3 to await RTV again", ConCommandFlag::AdminOnly);
  @g_ExcludePrevMaps = CCVar("iExcludePrevMaps", 0, "How many maps to exclude from nomination or voting", ConCommandFlag::AdminOnly);
  @g_PlaySounds = CCVar("bPlaySounds", 1, "Set to 1 to play sounds, set to 0 to not play sounds", ConCommandFlag::AdminOnly);

  MapActivate();

}

void MapInit()
{

  //Precache Sounds
  g_SoundSystem.PrecacheSound("fvox/one.wav");
  g_SoundSystem.PrecacheSound("fvox/two.wav");
  g_SoundSystem.PrecacheSound("fvox/three.wav");
  g_SoundSystem.PrecacheSound("fvox/four.wav");
  g_SoundSystem.PrecacheSound("fvox/five.wav");
  g_SoundSystem.PrecacheSound("puchi/spportal/tenseconds.wav");
  g_SoundSystem.PrecacheSound("gman/gman_choose1.wav");

}

void MapActivate()
{

  //Clean up Vars and Menus
  canRTV = false;
  isVoting = false;
  g_Scheduler.ClearTimerList();
  @g_TimeToVote = null;
  @g_TimeUntilVote = null;
  secondsleftforvote = g_VotingPeriodTime.GetInt();
  
  rtv_plr_data.resize(0);
  rtv_plr_data.resize(g_Engine.maxClients);

  for (int i = 1; i <= g_Engine.maxClients; i++)
  {

    CBasePlayer@ pPlayer = g_PlayerFuncs.FindPlayerByIndex(i);

    if(pPlayer !is null)
      AddPlayer(pPlayer);

  }

  forcenommaps.resize(0);
  maplist.resize(0);

  if(@rtvmenu !is null)
  {
    rtvmenu.Unregister();
    @rtvmenu = null;
  }
  if(@nommenu !is null)
  {
    nommenu.Unregister();
    @nommenu = null;
  }

  maplist = GetMapList();

  if (g_ExcludePrevMaps.GetInt() < 0)
    g_ExcludePrevMaps.SetInt(0);


  @g_TimeUntilVote = g_Scheduler.SetInterval("DecrementSeconds", 1, g_SecondsUntilVote.GetInt() + 1);

}

HookReturnCode Decider(SayParameters@ pParams)
{

  CBasePlayer@ pPlayer = pParams.GetPlayer();
  const CCommand@ pArguments = pParams.GetArguments();


  if (pArguments[0].ToLowercase() == "rtv")
  {

    RtvPush(@pArguments, @pPlayer);
    return HOOK_HANDLED;

  }
  else if (pArguments[0].ToLowercase() == "nom" || pArguments[0].ToLowercase() == "nominate")
  {

    pParams.ShouldHide = true;
    NomPush(@pArguments, @pPlayer);
    return HOOK_HANDLED;

  }
  else if (pArguments[0].ToLowercase() == "listnom" || pArguments[0].ToLowercase() == "nomlist")
  {

    pParams.ShouldHide = true;
    
    array<string> mapsNominated = GetNominatedMaps();

    for (uint i = 0; i < forcenommaps.length(); i++)
      mapsNominated.insertLast(forcenommaps[i]);

    if ( mapsNominated.length() == 0 )
    {

      MessageWarnPlayer(pPlayer, "No maps nominated currently\n");

    }
    else 
    {

      string cNoms = "";

      for (uint i = 0; i < mapsNominated.length(); i++)
      {

        cNoms += mapsNominated[i] + " ";

      }

      MessageWarnPlayer(pPlayer, "Current nominations: " + cNoms + "\n");

    }

    return HOOK_HANDLED;

  }
  else if (pArguments[0].ToLowercase() == "listmaps" || pArguments[0].ToLowercase() == "maplist")
  {

    pParams.ShouldHide = true;

    g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTCONSOLE, "[RTV] AVAILABLE MAPS:\n---------------------\n");

    string returnMaps = "";

    for(uint i = 0; i < maplist.length(); i++)
    {

      returnMaps += maplist[i] + " ";
      
      if(i % 3 == 0)
      {

        g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTCONSOLE, returnMaps + "\n");
        returnMaps = "";

      }

    }

    g_PlayerFuncs.ClientPrint(pPlayer, HUD_PRINTCONSOLE, "--------------------- count: " + maplist.length() + "\n");

    MessageWarnPlayer(pPlayer, "Map list written to console");

    return HOOK_HANDLED;

  }
  else return HOOK_CONTINUE;

}

HookReturnCode ResetVars()
{

  g_Scheduler.ClearTimerList();
  @g_TimeToVote = null;
  @g_TimeUntilVote = null;

  prevmaps.insertLast(string(g_Engine.mapname).ToLowercase());
  if ( (int(prevmaps.length()) > g_ExcludePrevMaps.GetInt()))
    prevmaps.removeAt(0);

  return HOOK_HANDLED;

}

HookReturnCode DisconnectCleanUp(CBasePlayer@ pPlayer)
{

  RTV_Data@ rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
  @rtvdataobj = null;

  return HOOK_HANDLED;

}

HookReturnCode AddPlayer(CBasePlayer@ pPlayer)
{

  RTV_Data@ rtvdataobj = RTV_Data(pPlayer);
  @rtv_plr_data[pPlayer.entindex() - 1] = @rtvdataobj;

  return HOOK_HANDLED;

}

//Main Functions
void DecrementSeconds()
{

  if (g_SecondsUntilVote.GetInt() == 0)
  {

    canRTV = true;
    g_Scheduler.RemoveTimer(g_TimeUntilVote);
    @g_TimeUntilVote = null;

  }
  else
  {

    g_SecondsUntilVote.SetInt(g_SecondsUntilVote.GetInt() - 1);

  }

}

void DecrementVoteSeconds()
{

  if (secondsleftforvote == g_VotingPeriodTime.GetInt() && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "gman/gman_choose1.wav", 1.0f, ATTN_NONE, 0, 100);


    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 10 && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "puchi/spportal/tenseconds.wav", 1.0f, ATTN_NONE, 0, 100);

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 5 && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "fvox/five.wav", 1.0f, ATTN_NONE, 0, 100);

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 4 && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "fvox/four.wav", 1.0f, ATTN_NONE, 0, 100);

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 3 && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "fvox/three.wav", 1.0f, ATTN_NONE, 0, 100);

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 2 && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "fvox/two.wav", 1.0f, ATTN_NONE, 0, 100);

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 1 && g_PlaySounds.GetBool())
  {

    g_SoundSystem.PlaySound(g_EntityFuncs.IndexEnt(0), CHAN_AUTO, "fvox/one.wav", 1.0f, ATTN_NONE, 0, 100);

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }
  else if (secondsleftforvote == 0 && g_PlaySounds.GetBool())
  {

    PostVote();
    g_Scheduler.RemoveTimer(g_TimeUntilVote);
    @g_TimeUntilVote = null;
    secondsleftforvote = g_VotingPeriodTime.GetInt();

  }
  else
  {

    string msg = string(secondsleftforvote) + " seconds left to vote.";
    g_PlayerFuncs.ClientPrintAll(HUD_PRINTCENTER, msg);
    secondsleftforvote--;

  }

}

void RtvPush(const CCommand@ pArguments, CBasePlayer@ pPlayer)
{

  if (isVoting)
  {

    rtvmenu.Open(0, 0, pPlayer);

  }
  else
  {
    if (canRTV)
    {

      RockTheVote(pPlayer);

    }
    else
    {

      MessageWarnAllPlayers( "RTV will enable in " + g_SecondsUntilVote.GetInt() + " seconds." );

    }

  }

}

void RtvPush(const CCommand@ pArguments)
{

  CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();

  if (isVoting)
  {

    rtvmenu.Open(0, 0, pPlayer);

  }
  else
  {
    if (canRTV)
    {

      RockTheVote(pPlayer);

    }
    else
    {

      MessageWarnAllPlayers( "RTV will enable in " + g_SecondsUntilVote.GetInt() + " seconds." );

    }

  }

}

void NomPush(const CCommand@ pArguments, CBasePlayer@ pPlayer)
{

  if (pArguments.ArgC() == 2)
  {

    NominateMap(pPlayer, pArguments.Arg(1));

  }
  else if (pArguments.ArgC() == 1)
  {

    NominateMenu(pPlayer);

  }

}


void NomPush(const CCommand@ pArguments)
{

  CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();

  if (pArguments.ArgC() == 2)
  {

    NominateMap(pPlayer,pArguments.Arg(1));

  }
  else if (pArguments.ArgC() == 1)
  {

    NominateMenu(pPlayer);

  }

}

void ForceVote(const CCommand@ pArguments, CBasePlayer@ pPlayer)
{

  if (pArguments.ArgC() >= 2)
  {

    array<string> rtvList;

    for (int i = 1; i < pArguments.ArgC(); i++)
    {

      if (g_EngineFuncs.IsMapValid(pArguments.Arg(i)))
        rtvList.insertLast(pArguments.Arg(i));
      else
        MessageWarnPlayer(pPlayer, pArguments.Arg(i) + " is not a valid map. Skipping...");

    }

    VoteMenu(rtvList);
    @g_TimeToVote = g_Scheduler.SetInterval("DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);

  }
  else if (pArguments.ArgC() == 1)
  {

    BeginVote();
    @g_TimeToVote = g_Scheduler.SetInterval("DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);

  }

}

void ForceVote(const CCommand@ pArguments)
{

  CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();

  if (pArguments.ArgC() >= 2)
  {

    array<string> rtvList;

    for (int i = 1; i < pArguments.ArgC(); i++)
    {

      if (g_EngineFuncs.IsMapValid(pArguments.Arg(i)))
        rtvList.insertLast(pArguments.Arg(i));
      else
        MessageWarnPlayer(pPlayer, pArguments.Arg(i) + " is not a valid map. Skipping...");

    }

    VoteMenu(rtvList);
    @g_TimeToVote = g_Scheduler.SetInterval("DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);

  }
  else if (pArguments.ArgC() == 1)
  {

    BeginVote();
    @g_TimeToVote = g_Scheduler.SetInterval("DecrementVoteSeconds", 1,g_VotingPeriodTime.GetInt() + 1);

  }

}

void AddNominateMap(const CCommand@ pArguments)
{

  CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
  array<string> plrnom = GetNominatedMaps();


  if (pArguments.ArgC() == 1)
  {

    MessageWarnPlayer(pPlayer, "You did not specify a map to nominate. Try again.");
    return;

  }

  if (g_EngineFuncs.IsMapValid(pArguments.Arg(1)))
  {

    if ( (plrnom.find(pArguments.Arg(1)) < 0) && (forcenommaps.find(pArguments.Arg(1)) < 0) )
    {

      forcenommaps.insertLast(pArguments.Arg(1));
      MessageWarnPlayer(pPlayer, "Map was added to force nominated maps list");

    }
    else
      MessageWarnPlayer(pPlayer, "Map was already nominated by someone else. Skipping...");

  }
  else
    MessageWarnPlayer(pPlayer, "Map does not exist. Skipping...");


}

void RemoveNominateMap(const CCommand@ pArguments)
{

  CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
  array<string> plrnom = GetNominatedMaps();


  if (pArguments.ArgC() == 1)
  {

    MessageWarnPlayer(pPlayer, "You did not specify a map to remove from nominations. Try again.");
    return;

  }


    if (plrnom.find(pArguments.Arg(1)) >= 0)
    {

      //Let's figure out who nominated that map and remove it...
      for (uint i = 0; i < rtv_plr_data.length(); i++)
      {

          if (@rtv_plr_data[i] !is null)
          {

            if (rtv_plr_data[i].szNominatedMap == pArguments.Arg(1))
              {

                MessageWarnAllPlayers( string(rtv_plr_data[i].szPlayerName + " has removed " + rtv_plr_data[i].szPlayerName + " nomination of " + rtv_plr_data[i].szNominatedMap));
                rtv_plr_data[i].szNominatedMap = "";

              }

          }
      }

    }
    else if (forcenommaps.find(pArguments.Arg(1)) >= 0)
    {

      forcenommaps.removeAt(forcenommaps.find(pArguments.Arg(1)));
      MessageWarnPlayer(pPlayer, pArguments.Arg(1) +  " was removed from admin's nominations");

    }
    else MessageWarnPlayer(pPlayer, pArguments.Arg(1) + " was not nominated. Skipping...");

}

void CancelVote(const CCommand@ pArguments)
{

  CBasePlayer@ pPlayer = g_ConCommandSystem.GetCurrentPlayer();
  RTV_Data@ rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];

  g_Scheduler.RemoveTimer(@g_TimeToVote);
  CScheduledFunction@ g_TimeToVote = null;

  ClearRTV();

  MessageWarnAllPlayers( "The vote has been cancelled by " + string(rtvdataobj.szPlayerName) );

}

void MessageWarnPlayer(CBasePlayer@ pPlayer, string msg)
{

  g_PlayerFuncs.SayText( pPlayer, "[RTV] " + msg + "\n");

}

void MessageWarnAllPlayers(string msg)
{

  g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, "[RTV] " + msg + "\n" );

}


void NominateMap( CBasePlayer@ pPlayer, string szMapName )
{

  RTV_Data@ rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
  array<string> mapsNominated = GetNominatedMaps();
  array<string> mapList = maplist;


  if ( mapList.find( szMapName ) < 0 )
  {

    MessageWarnPlayer( pPlayer, "Map does not exist." );
    return;

  }

  if ( prevmaps.find( szMapName ) >= 0)
  {

    MessageWarnPlayer( pPlayer, "Map has already been played and will be excluded until later.");
    return;

  }

  if ( forcenommaps.find( szMapName ) >= 0 )
  {

    MessageWarnPlayer( pPlayer, "\"" + szMapName + "\" was found in the admin's list of nominated maps.");
    return;

  }

  if ( mapsNominated.find( szMapName ) >= 0 )
  {

    MessageWarnPlayer( pPlayer, "Someone nominated \"" + szMapName + "\" already.");
    return;

  }

  if ( string( g_Engine.mapname ).ToLowercase() == szMapName )
  {

    MessageWarnPlayer( pPlayer, "Can't nominate the current map.");
    return;

  }

  if ( int(mapsNominated.length()) > g_MaxMapsToVote.GetInt() )
  {

    MessageWarnPlayer( pPlayer, "Players have reached maxed number of nominations!" );
    return;

  }

  if ( rtvdataobj.szNominatedMap.IsEmpty() )
  {

    MessageWarnAllPlayers( rtvdataobj.szPlayerName + " has nominated \"" + szMapName + "\"." );
    rtvdataobj.szNominatedMap = szMapName;
    return;

  }
  else
  {

    MessageWarnAllPlayers( rtvdataobj.szPlayerName + " has changed their nomination to \"" + szMapName + "\". " );
    rtvdataobj.szNominatedMap = szMapName;
    return;

  }

}

void nominate_MenuCallback( CTextMenu@ nommenu, CBasePlayer@ pPlayer, int page, const CTextMenuItem@ item)
{

  if ( item !is null && pPlayer !is null )
    NominateMap( pPlayer,item.m_szName );

  if ( @nommenu !is null && nommenu.IsRegistered() )
  {

    nommenu.Unregister();
    @nommenu = null;

  }

}

void NominateMenu( CBasePlayer@ pPlayer )
{

      @nommenu = CTextMenu(@nominate_MenuCallback);
      nommenu.SetTitle("Nominate...");

      array<string> mapList = maplist;

      //Remove any maps found in the previous map exclusion list or force nominated maps
      for (uint i = 0; i < mapList.length();)
      {

        if ((prevmaps.find(mapList[i]) >= 0))
          mapList.removeAt(i);
        else if((forcenommaps.find(mapList[i]) >= 0))
          mapList.removeAt(i);
        else
          ++i;

      }

      mapList.sortAsc();

      for (uint i = 0; i < mapList.length(); i++)
        nommenu.AddItem( mapList[i], any(mapList[i]));

      if (!(nommenu.IsRegistered()))
        nommenu.Register();

      nommenu.Open( 0, 0, pPlayer );

}

void RockTheVote(CBasePlayer@ pPlayer)
{

  RTV_Data@ rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];
  int rtvRequired = CalculateRequired();

  if (rtvdataobj.bHasRTV)
  {

    MessageWarnPlayer(pPlayer,"You have already Rocked the Vote!");

  }
  else
  {

    rtvdataobj.bHasRTV = true;
    MessageWarnPlayer(pPlayer,"You have Rocked the Vote!");
    MessageWarnAllPlayers("" + GetRTVd() + " of " + rtvRequired + " players until vote initiates!");

  }

  if (GetRTVd() >= rtvRequired)
  {

    if (!isVoting)
    {

      isVoting = true;
      BeginVote();

    }

    @g_TimeToVote = g_Scheduler.SetInterval("DecrementVoteSeconds", 1,g_VotingPeriodTime.GetInt() + 1);

  }

}

void rtv_MenuCallback(CTextMenu@ rtvmenu, CBasePlayer@ pPlayer, int page, const CTextMenuItem@ item)
{

  if (item !is null && pPlayer !is null)
    vote(item.m_szName,pPlayer);

}

void VoteMenu(array<string> rtvList)
{

  canRTV = true;
  MessageWarnAllPlayers( "You have " + g_VotingPeriodTime.GetInt() + " seconds to vote!");

  @rtvmenu = CTextMenu(@rtv_MenuCallback);
  rtvmenu.SetTitle("RTV Vote");
  for (uint i = 0; i < rtvList.length(); i++)
  {

    rtvmenu.AddItem(rtvList[i], any(rtvList[i]));

  }

  if (!(rtvmenu.IsRegistered()))
  {

    rtvmenu.Register();

  }

  for (int i = 1; i <= g_Engine.maxClients; i++)
  {

    CBasePlayer@ pPlayer = g_PlayerFuncs.FindPlayerByIndex(i);

    if(pPlayer !is null)
    {

      rtvmenu.Open(0, 0, pPlayer);

    }

  }

}

void vote(string votedMap,CBasePlayer@ pPlayer)
{

  RTV_Data@ rtvdataobj = @rtv_plr_data[pPlayer.entindex() - 1];

  if (rtvdataobj.szVotedMap.IsEmpty())
  {

    rtvdataobj.szVotedMap = votedMap;
    MessageWarnPlayer(pPlayer,"You voted for " + votedMap);

  }
  else
  {

    rtvdataobj.szVotedMap = votedMap;
    MessageWarnPlayer(pPlayer,"You changed your vote to "+ votedMap);

  }


}

void BeginVote()
{

  canRTV = true;

  array<string> rtvList;
  array<string> mapsNominated = GetNominatedMaps();

  for (uint i = 0; i < forcenommaps.length(); i++)
    rtvList.insertLast(forcenommaps[i]);

  for (uint i = 0; i < mapsNominated.length(); i++)
    rtvList.insertLast(mapsNominated[i]);

  //Determine how many more maps need to be added to menu
  int remaining = 0;
  if(int(maplist.length()) < g_MaxMapsToVote.GetInt() )
  {

    //maplist is smaller, use it
    remaining = int(maplist.length() - rtvList.length());

  }
  else if (int(maplist.length()) > g_MaxMapsToVote.GetInt() )
  {

    //MaxMaps is smaller, use it
    remaining = g_MaxMapsToVote.GetInt() - int(rtvList.length());

  }
  else if (int(maplist.length()) == g_MaxMapsToVote.GetInt() )
  {

    //They are same length, use maplist
    remaining = int(maplist.length() - rtvList.length());

  }

  while (remaining > 0)
  {

    //Fill rest of menu with random maps
    string rMap = RandomMap();

    if ( ((rtvList.find(rMap)) < 0) && (prevmaps.find(rMap) < 0))
    {

      rtvList.insertLast(rMap);
      remaining--;

    }

  }


  //Give Menus to Vote!
  VoteMenu(rtvList);

}

void PostVote()
{

  array<string> rtvList = GetVotedMaps();
  dictionary rtvVotes;
  int highestVotes = 0;

  //Initialize Dictionary of votes
  for (uint i = 0; i < rtvList.length(); i++)
  {

    rtvVotes.set( rtvList[i], 0);

  }

  for (uint i = 0; i < rtvList.length(); i++)
  {

    int val = int(rtvVotes[rtvList[i]]);
    rtvVotes[rtvList[i]] = val + 1;

  }

  //Find highest amount of votes
  for (uint i = 0; i < rtvList.length(); i++)
  {

    if ( int( rtvVotes[rtvList[i]] ) >= highestVotes)
    {

      highestVotes = int(rtvVotes[rtvList[i]]);

    }
  }

  //Nobody voted?
  if (highestVotes == 0)
  {

    string chosenMap = RandomMap();
    MessageWarnAllPlayers( "\"" + chosenMap +"\" has been randomly chosen since nobody picked");
    ChooseMap(chosenMap, false);
    return;

  }

  //Find how many maps were voted at the highest
  array<string> candidates;
  array<string> singlecount = rtvVotes.getKeys();
  for (uint i = 0; i < singlecount.length(); i++)
  {

    if ( int(rtvVotes[singlecount[i]]) == highestVotes)
    {

      candidates.insertLast( singlecount[i] );

    }
  }
  singlecount.resize(0);

  //Revote or random choose if more than one map is at highest vote count
  if (candidates.length() > 1)
  {

    if (g_ChooseEnding.GetInt() == 1)
    {

      ClearVotedMaps();
      MessageWarnAllPlayers( "There was a tie! Revoting...");
      @g_TimeToVote = g_Scheduler.SetInterval("DecrementVoteSeconds", 1, g_VotingPeriodTime.GetInt() + 1);
      VoteMenu(candidates);
      return;

    }
    else if (g_ChooseEnding.GetInt() == 2)
    {

      string chosenMap = RandomMap(candidates);
      MessageWarnAllPlayers( "\"" + chosenMap +"\" has been randomly chosen amongst the tied");
      ChooseMap(chosenMap, false);
      return;

    }
    else if (g_ChooseEnding.GetInt() == 3)
    {

      ClearVotedMaps();
      ClearRTV();

      MessageWarnAllPlayers( "There was a tie! Please RTV again...");

    }
    else
      g_Log.PrintF("[RTV] Fix your ChooseEnding CVar!\n");
  }
  else
  {

    MessageWarnAllPlayers( "\"" + candidates[0] +"\" has been chosen!");
    ChooseMap(candidates[0], false);
    return;

  }

}

void ChooseMap(string chosenMap, bool forcechange)
{

  //After X seconds passed or if CVar WhenToChange is 0
  if (forcechange || (g_WhenToChange.GetInt() == 0) )
  {

    g_Log.PrintF("[RTV] Changing map to \"%1\"\n", chosenMap);
    //g_EngineFuncs.ChangeLevel(chosenMap);
    g_EngineFuncs.ServerCommand("changelevel " + chosenMap + "\n");

  }
  //Change after X Seconds
  if (g_WhenToChange.GetInt() > 0)
  {

    NetworkMessage message(MSG_ALL, NetworkMessages::SVC_INTERMISSION, null);
    message.End();

    g_Scheduler.SetTimeout("ChooseMap", g_WhenToChange.GetInt(), chosenMap, true);

  }
  //Change after map end
  if (g_WhenToChange.GetInt() < 0)
  {

    //Handle "infinite time left" maps by setting time left to X minutes
    if (g_EngineFuncs.CVarGetFloat("mp_timelimit") == 0)
    {

      g_Scheduler.SetTimeout("ChooseMap", abs(g_WhenToChange.GetInt()), chosenMap, true);

    }

    g_EngineFuncs.ServerCommand("mp_nextmap "+ chosenMap + "\n");
    g_EngineFuncs.ServerCommand("mp_nextmap_cycle "+ chosenMap + "\n");
    MessageWarnAllPlayers( "Next map has been set to \"" + chosenMap + "\".");

  }

}

// Utility Functions

int CalculateRequired()
{

  return int(ceil( g_PlayerFuncs.GetNumPlayers() * (g_PercentageRequired.GetInt() / 100.0f) ));

}

string RandomMap()
{

  return maplist[pcg_gen.nextInt(maplist.length())];

}

string RandomMap(array<string> mapList)
{

  return mapList[pcg_gen.nextInt(mapList.length())];

}

string RandomMap(array<string> mapList, uint length)
{

  return mapList[pcg_gen.nextInt(length)];

}

array<string> GetNominatedMaps()
{

  array<string> nommaps;

  for (uint i = 0; i < rtv_plr_data.length(); i++)
  {

    RTV_Data@ pPlayer = @rtv_plr_data[i];

    if (pPlayer !is null)
      if ( !(pPlayer.szNominatedMap.IsEmpty()) )
        nommaps.insertLast(pPlayer.szNominatedMap);

  }


  return nommaps;

}

array<string> GetMapList()
{

  array<string> mapList;

  if ( !(g_MapList.GetString() == "mapcycle.txt" ) )
  {

    File@ file = g_FileSystem.OpenFile(g_MapList.GetString(), OpenFile::READ);

    if(file !is null && file.IsOpen())
    {

      while(!file.EOFReached())
      {

        string sLine;
        file.ReadLine(sLine);

        if(sLine.SubString(0,2) == "//" || sLine.IsEmpty())
          continue;

        sLine.Trim();
  
        if ( g_MapList.GetString() == "scripts/plugins/cfg/mapvote.cfg" )
        {
	  array<string> parsed = sLine.Split(" ");

          if(parsed.length() < 2)
            continue;

          mapList.insertLast(parsed[1]);
        }
        else {
          mapList.insertLast(sLine);
        }
      }

      file.Close();

      //Probably wanna make sure all maps are valid...
      for (uint i = 0; i < mapList.length();)
      {

        if ( !(g_EngineFuncs.IsMapValid(mapList[i])) )
        {

          mapList.removeAt(i);

        }
        else
          ++i;

      }

    }

    return mapList;

  }

  return g_MapCycle.GetMapCycle();

}


array<string> GetVotedMaps()
{

  array<string> votedmaps;

  for (uint i = 0; i < rtv_plr_data.length(); i++)
  {

    if (@rtv_plr_data[i] !is null)
      if ( !(rtv_plr_data[i].szVotedMap.IsEmpty()) )
        votedmaps.insertLast(rtv_plr_data[i].szVotedMap);

  }

  return votedmaps;

}

int GetRTVd()
{

  int counter = 0;
  for (uint i = 0; i < rtv_plr_data.length(); i++)
  {

    if (@rtv_plr_data[i] !is null)
      if (rtv_plr_data[i].bHasRTV)
        counter += 1;

  }

  return counter;

}

void ClearVotedMaps()
{

  for (uint i = 0; i < rtv_plr_data.length(); i++)
  {

    if (@rtv_plr_data[i] !is null)
    {

      rtv_plr_data[i].szVotedMap = "";

    }

  }

}

void ClearRTV()
{

  for (uint i = 0; i < rtv_plr_data.length(); i++)
  {

    if (@rtv_plr_data[i] !is null)
    {

      rtv_plr_data[i].bHasRTV = false;

    }

  }

}
