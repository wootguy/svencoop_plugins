void PluginInit() {
  g_Module.ScriptInfo.SetAuthor("lunchbox & incognico");
  g_Module.ScriptInfo.SetContactInfo("irc://irc.rizon.net/#/dev/null");
  g_Hooks.RegisterHook( Hooks::Player::ClientPutInServer, @ClientPutInServer);
}

CClientCommand g_ListPrecacheModels("listprecachedplayermodels", "List precached player model list", @ListPrecachePlayerModels);

array<string> g_ModelList;

HookReturnCode ClientPutInServer(CBasePlayer@ pPlayer)
{
    KeyValueBuffer@ p_PlayerInfo = g_EngineFuncs.GetInfoKeyBuffer(pPlayer.edict());
    if( g_ModelList.find(p_PlayerInfo.GetValue("model")) < 0) {
      string lowermodel = p_PlayerInfo.GetValue("model").ToLowercase();
      g_Game.AlertMessage(at_console, "Adding model to precache:" + lowermodel);
      g_ModelList.insertLast(lowermodel);
    }

    return HOOK_HANDLED;
}

void MapInit() {
  for (uint i = 0; i < g_ModelList.length(); i++) {
    g_Game.PrecacheGeneric("models/player/" + g_ModelList[i] + "/" + g_ModelList[i] + ".mdl");
  }
}

void MapStart() {
  g_ModelList.resize(0);
}

void ListPrecachePlayerModels(const CCommand@ pArgs) {
  CBasePlayer@ pCaller = g_ConCommandSystem.GetCurrentPlayer();
  g_PlayerFuncs.ClientPrint(pCaller, HUD_PRINTCONSOLE, "Current playermodel precache list:\n");
  for (uint i = 0; i < g_ModelList.length(); i++) {
    g_PlayerFuncs.ClientPrint(pCaller, HUD_PRINTCONSOLE, g_ModelList[i] + "\n");
  }
}
