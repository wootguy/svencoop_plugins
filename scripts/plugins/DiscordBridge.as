const string g_BridgeFile = "scripts/plugins/store/discordbridge.txt";

string lastMap = "";

void PluginInit() {
  g_Module.ScriptInfo.SetAuthor("animaliZed");
  g_Module.ScriptInfo.SetContactInfo("irc://irc.rizon.net/#/dev/null");
}

void MapStart() {
  if( g_Scheduler.GetCurrentFunction() !is null )
    g_Scheduler.ClearTimerList();

  g_Scheduler.SetTimeout( "AnnounceMap", 25 );
}

void AnnounceMap() {
  int numPlayers = 0;

  CBasePlayer@ pPlayer = null;
  for( int i = 1; i <= g_Engine.maxClients; ++i ) {
    @pPlayer = g_PlayerFuncs.FindPlayerByIndex( i );

    if( pPlayer !is null && pPlayer.IsConnected() )
      numPlayers++;
  }

  if( numPlayers == 0 || g_Engine.mapname == lastMap )
    return;

  lastMap = g_Engine.mapname;

  string append = "" + g_Engine.mapname + " " + numPlayers + "\n";
  AppendFile( append );
}

void AppendFile( string append ) {
  File@ pFile = g_FileSystem.OpenFile( g_BridgeFile, OpenFile::APPEND );

  if ( pFile !is null && pFile.IsOpen() ) {
    pFile.Write( append );
    pFile.Close();
  }
}
