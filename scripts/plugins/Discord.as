File@ f_FromSven;
File@ f_ToSven;

CScheduledFunction@ sf_LinkChat    = null;
CScheduledFunction@ sf_StatusTimer = null;

const string g_FromSven = "scripts/plugins/store/chatfromsven.txt";
const string g_ToSven   = "scripts/plugins/store/chattosven.txt";

string lastMap  = "";
string lastFrom = "";
string lastTo   = "";

void PluginInit() {
  g_Module.ScriptInfo.SetAuthor("incognico");
  g_Module.ScriptInfo.SetContactInfo("irc://irc.rizon.net/#/dev/null");

  g_Hooks.RegisterHook(Hooks::Player::ClientSay, @ClientSay);
//  g_Hooks.RegisterHook(Hooks::Player::ClientDisconnect, @ClientDisconnect);
//  g_Hooks.RegisterHook(Hooks::Player::ClientPutInServer, @ClientPutInServer);

  MapStart();
}

void MapStart() {
  TruncateFromSven();
  FlushFromSven();

  if ( sf_LinkChat is null )
    @sf_LinkChat = g_Scheduler.SetInterval( "ChatLink", 1.5f );

  if ( sf_StatusTimer !is null )
    g_Scheduler.RemoveTimer( sf_StatusTimer );

  @sf_StatusTimer = g_Scheduler.SetTimeout( "ServerStatus", 25 ); // will be 0 at MapStart() otherwise

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

    if ( sLine.IsEmpty() || lastTo == sLine )
      continue;

    g_PlayerFuncs.ClientPrintAll( HUD_PRINTTALK, sLine + "\n" );
    lastTo = sLine;

    truncate = true;
  }

  f_ToSven.Close();

  if ( truncate ) {
    @f_ToSven = g_FileSystem.OpenFile( g_ToSven, OpenFile::WRITE );
    f_ToSven.Write( null );
    f_ToSven.Close();
  }
}

void AppendFromSven( string append ) {
    f_FromSven.Write( append );
}

HookReturnCode ClientSay( SayParameters@ pParams ) {
  const CCommand@ pArgs = pParams.GetArguments();

  if ( pArgs.ArgC() < 1 || lastFrom == pParams.GetCommand() )
     return HOOK_CONTINUE;

  CBasePlayer@ pPlayer = pParams.GetPlayer();

  AppendFromSven( "<" + pPlayer.pev.netname + "> " + pParams.GetCommand() + "\n" );
  lastFrom = pParams.GetCommand();

  return HOOK_CONTINUE;
}

/* too spammy

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
*/
