// config:
// files must exist before loading this script !!!
const string g_FromSven = "scripts/plugins/store/_fromsven.txt";
const string g_ToSven   = "scripts/plugins/store/_tosven.txt";
const bool joinsquits   = false; // also writes joining and leaving players (spammy)
const float delay       = 1.75f; // flush this often (sec.), don't set too low
const float statusdelay = 25.0f; // wait this long after map change before writing status line (player count will be too low if this is set to ~0-10)
//////////

File@ f_FromSven;
File@ f_ToSven;
CScheduledFunction@ sf_LinkChat    = null;
CScheduledFunction@ sf_StatusTimer = null;
string lastMap = "";

void PluginInit() {
  g_Module.ScriptInfo.SetAuthor("incognico");
  g_Module.ScriptInfo.SetContactInfo("irc://irc.rizon.net/#/dev/null");

  g_Hooks.RegisterHook(Hooks::Game::MapChange, @MapChange);
  g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);

  if ( joinsquits ) {
    g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientDisconnect);
    g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientPutInServer);
  }

  MapInit();
}

void MapInit() {
  FlushFromSven();

  if ( sf_LinkChat is null )
    @sf_LinkChat = g_Scheduler.SetInterval( "ChatLink", delay );

  if ( sf_StatusTimer !is null )
    g_Scheduler.RemoveTimer( sf_StatusTimer );

  @sf_StatusTimer = g_Scheduler.SetTimeout( "ServerStatus", statusdelay );

  if ( g_Engine.mapname == "_server_start" )
    return;
  
  string append = "map " + g_Engine.mapname + "\n";
  AppendFromSven( append );
}

void ServerStatus() {
  if( g_PlayerFuncs.GetNumPlayers() == 0 || g_Engine.mapname == lastMap )
    return;

  lastMap = g_Engine.mapname;

  string append = "status " + g_Engine.mapname + " " + g_PlayerFuncs.GetNumPlayers() + "\n";
  AppendFromSven( append );
}

void ChatLink() {
  FlushFromSven();
  FlushToSven();
}

void FlushFromSven() {
  if ( f_FromSven !is null && f_FromSven.IsOpen() )
    f_FromSven.Close();

  @f_FromSven = g_FileSystem.OpenFile( g_FromSven, OpenFile::APPEND );
}

void TruncateFromSven() {
  if ( f_FromSven !is null && f_FromSven.IsOpen() )
    f_FromSven.Close();

  @f_FromSven = g_FileSystem.OpenFile( g_FromSven, OpenFile::WRITE );
  f_FromSven.Write( null );
  f_FromSven.Close();
}

void FlushToSven() {
  if ( f_ToSven !is null && f_ToSven.IsOpen() )
    f_ToSven.Close();

  bool truncate = false;

  @f_ToSven = g_FileSystem.OpenFile( g_ToSven, OpenFile::READ );

  while ( !f_ToSven.EOFReached() ) {
    string sLine;
    f_ToSven.ReadLine( sLine );

    if ( sLine.IsEmpty() )
      continue;

    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, sLine + "\n" );

    truncate = true;
  }

  f_ToSven.Close();

  if ( truncate )
    TruncateToSven();
}
  
void TruncateToSven() {
  @f_ToSven = g_FileSystem.OpenFile( g_ToSven, OpenFile::WRITE );
  f_ToSven.Write( null );
  f_ToSven.Close();
}

void AppendFromSven( string append ) {
  f_FromSven.Write( append );
}

HookReturnCode MapChange() {
  if ( sf_LinkChat !is null )
    g_Scheduler.RemoveTimer( sf_LinkChat );

  TruncateFromSven();

  return HOOK_CONTINUE;
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
  const CCommand@ pArgs = pParams.GetArguments();

  if ( pArgs.ArgC() < 1 )
     return HOOK_CONTINUE;

  CBasePlayer@ pPlayer = pParams.GetPlayer();
  const string steamId = g_EngineFuncs.GetPlayerAuthId( pPlayer.edict() );

  AppendFromSven( "<" + pPlayer.pev.netname + "><" + steamId + "> " + pParams.GetCommand() + "\n" );

  return HOOK_CONTINUE;
}

HookReturnCode ClientPutInServer( CBasePlayer@ pPlayer ) {
  const string steamId = g_EngineFuncs.GetPlayerAuthId( pPlayer.edict() );

  AppendFromSven( "+ <" + pPlayer.pev.netname + "><" + steamId + "> has joined the game\n" );

  return HOOK_CONTINUE;
}

HookReturnCode ClientDisconnect( CBasePlayer@ pPlayer ) {
  const string steamId = g_EngineFuncs.GetPlayerAuthId( pPlayer.edict() );

  AppendFromSven( "- <" + pPlayer.pev.netname + "><" + steamId + "> has left the game\n" );

  return HOOK_CONTINUE;
}
