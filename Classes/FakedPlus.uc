/**
 * Author NikC-
 */

class FakedPlus extends Mutator
	Config(FakedPlus)
	abstract;


var() config bool bNoDrama;			// slomo switch
var() config bool bAdminOnly;		// forbid other players to use mutate
var() config bool bSoloMode;		// leave only 1 free slot

var() config int minNumPlayers;		// int for zed hp calculation

var int nFakes;						// main int which controlls fakes amount
var int ServerSpectatorNum;			// server's spectator slots
var int ReservedPlayerSlots;

var bool bLockOn;					// detects server lock (mutate lock on)
var bool bRefreshMaxPlayers;
var bool bUseReservedSlots;

var KFGameType KFGT;


function PostBeginPlay()
{
	local bool bInitialized;

	if(bInitialized)
		return;
	bInitialized = true;

	KFGT = KFGameType(level.game);
	if(KFGT == none)
	{
		Log("KFGameType not found!!!!!!");
	}

	// keep in mind server's spectator count
	ServerSpectatorNum = KFGT.MaxSpectators;
	// SaveConfig();

	SetTimer(1.0,true);
}


function Timer()
{
	// controll over slomo
	if(bNoDrama)
		KFGT.LastZedTimeEvent = Level.TimeSeconds;

	// apply bSoloMode or custom slot settings
	if(bRefreshMaxPlayers)
		AdjustPlayerSlots();

	// my OCD doesnt like when empty servers are on top of the list
	if(KFGT.IsInState('PendingMatch'))
	{
		if(RealPlayers() == 0)
		{
			KFGT.NumPlayers = 0;
			return;
		}

		else
		{
			KFGT.NumPlayers = nFakes + RealPlayers();
			return;
		}
	}

	else if(KFGT.IsInState('MatchInProgress'))
	{
		KFGT.NumPlayers = nFakes + RealPlayers();
		return;
	}

	// do this to make map voting less painfull and instant after we wipe
	else if(KFGT.IsInState('MatchOver'))
	{
		KFGT.NumPlayers = RealPlayers();
	}
}


function AdjustPlayerSlots()
{
  bRefreshMaxPlayers = false;

	if(bSoloMode)
	{
		KFGT.MaxPlayers = nFakes + 1;
		return;
	}

	if(bUseReservedSlots)
    KFGT.MaxPlayers = nFakes + ReservedPlayerSlots;
}


// count non-spectator players
function int RealPlayers()
{
	local Controller c;
	local int realPlayersCount;
	
	for( c = Level.ControllerList; c != none; c = c.NextController )
		if ( c.IsA('PlayerController') && c.PlayerReplicationInfo != none && !c.PlayerReplicationInfo.bOnlySpectator )
			realPlayersCount++;

	return realPlayersCount;
}


// count currently alive players
function int AlivePlayersAmount()
{
	local Controller c;
	local int alivePlayersCount;

	for( c = Level.ControllerList; c != none; c = c.NextController )
		if( c.IsA('PlayerController') && c.Pawn != none && c.Pawn.Health > 0 )
			alivePlayersCount ++;

	return alivePlayersCount;
}


// change zed health, works similar to HP config mut
function bool CheckReplacement(Actor Other, out byte bSuperRelevant)
{
  local KFMonster monster;
	local int alivePlayersCount;

  monster = KFMonster(Other);
	if(monster != none)
	{
		alivePlayersCount = AlivePlayersAmount();
		if (alivePlayersCount < minNumPlayers)
		{
			monster.Health *= hpScale(monster.PlayerCountHealthScale) / monster.NumPlayersHealthModifer();
			monster.HealthMax = monster.Health;
			monster.HeadHealth *= hpScale(monster.PlayerNumHeadHealthScale) / monster.NumPlayersHeadHealthModifer();

			monster.MeleeDamage /= 0.75;
			monster.ScreamDamage /= 0.75;
			monster.SpinDamConst /= 0.75;
			monster.SpinDamRand /= 0.75;
		}
	}
	return true;
}


function float hpScale(float hpScale)
{
	return 1.0 + (minNumPlayers - 1) * hpScale;
}


//=========================================================================
// split our mutate cmd so we can use fancy ON / OFF switches
function array<string> SplitString(string inputString, string div)
{
	local array<string> parts;
	local bool bEOL;
	local string tempChar;
	local int preCount, curCount, partCount, strLength;
	strLength = Len(inputString);
	if(strLength == 0)
		return parts;
	bEOL = false;
	preCount = 0;
	curCount = 0;
	partCount = 0;

	while(!bEOL)
	{
		tempChar = Mid(inputString, curCount, 1);
		if(tempChar != div)
			curCount ++;
		else
		{
			if(curCount == preCount)
			{
				curCount ++;
				preCount ++;
			}

			else
			{
				parts[partCount] = Mid(inputString, preCount, curCount - preCount);
				partCount ++;
				preCount = curCount + 1;
				curCount = preCount;
			}
		}

		if(curCount == strLength)
		{
			if(preCount != strLength)
				parts[partCount] = Mid(inputString, preCount, curCount);
			bEOL = true;
		}
	}

	return parts;
}


function bool CheckAdmin(PlayerController Sender)
{
	if ( (Sender.PlayerReplicationInfo != none && Sender.PlayerReplicationInfo.bAdmin) || Level.NetMode == NM_Standalone || Level.NetMode == NM_ListenServer )
		return true;

	SendMessage(Sender, "%wRequires %rADMIN %wprivileges!");
	return false;
}


function Mutate(string MutateString, PlayerController Sender)
{
	local int i,zedHP;
	local array<String> wordsArray;
	local String command, mod;
	local array<String> modArray;

	if(bAdminOnly)
	{
		if(!CheckAdmin(Sender))
			return;
	}

	else
	{
		if(Sender.PlayerReplicationInfo.bOnlySpectator && !CheckAdmin(Sender))
			return;
	}

	// ignore empty cmds and dont go further
	wordsArray = SplitString(MutateString, " ");
	if(wordsArray.Length == 0)
		return;

	// do stuff with our cmd
	command = wordsArray[0];
	if(wordsArray.Length > 1)
		mod = wordsArray[1];
	else
		mod = "";

	i = 0;
	while(i + 1 < wordsArray.Length || i < 10)
	{
		if(i + 1 < wordsArray.Length)
			modArray[i] = wordsArray[i+1];
		else
			modArray[i] = "";
		i ++;
	}

	// 'mutate hlp'
	if(command ~= "HELP" || command ~= "HLP" || command ~= "HALP")
	{
		// Helper class. Allows to type 'mutate help <cmd>' and get detailed description
		class'FakedPlus.Helper'.static.TellAbout(mod, Sender, Self);
	}

	// changes fakes amount
	else if(command ~= "FAKED" || command ~= "FAKE" || command ~= "FAKES")
	{
		if(Int(mod) >= 0 && Int(mod) <= 5)
		{
			nFakes = Int(mod);
			if(bLockOn)
				KFGT.MaxPlayers = RealPlayers() + nFakes;
			BroadcastText("%wFaked players - %b"$Int(mod), true);
		}
	}

	// change zed health
	else if(command ~= "HEALTH" || command ~= "HP")
	{
		// limit health to 1-6
		zedHP = Clamp(Int(mod),1,6);

		minNumPlayers = zedHP;
		BroadcastText("%wZeds minimal health is forced to - %b"$zedHP, true);
	}

  else if(command ~= "SOLO")
  {
    if(mod ~= "ON")
		{
			bSoloMode = true;
      SaveConfig();
			BroadcastText("%wSolo mode - %b"$mod, true);
		}

		else if(mod ~= "OFF")
		{
			bSoloMode = false;
      SaveConfig();
			BroadcastText("%wSolo mode - %b"$mod, true);
		}
  }

	// makes player slots equal to player+fakes amount, and prevents other people from joining
	else if(command ~= "LOCK" || command ~= "PLAYER" || command ~= "PLAYERS" || command ~= "SLOT")
	{
		if(mod ~= "ON")
		{
			KFGT.MaxPlayers = RealPlayers() + nFakes;
			bLockOn = true;
			BroadcastText("%wServer is %rLocked!", true);
		}

		else if(mod ~= "OFF")
		{
			KFGT.MaxPlayers = 6;
			bLockOn = false;
			BroadcastText("%wServer is %rUnlocked!", true);
		}

		else
		{
			KFGT.MaxPlayers = Int(mod);
			BroadcastText("%wPlayer slots are set to - %b"$Int(mod), true);
		}
	}

	// trader skip, doesnt work for actual waves
	else if(command ~= "SKIP" || command ~= "SKP")
	{
		if (!KFGT.bWaveInProgress && KFGT.waveNum <= KFGT.finalWave && KFGT.waveCountDown > 1)
		{
			KFGT.waveCountDown = 1;
			if (InvasionGameReplicationInfo(KFGT.GameReplicationInfo) != none)
				InvasionGameReplicationInfo(KFGT.GameReplicationInfo).waveNumber = KFGT.waveNum;
			BroadcastText("%wTrader time skipped!", true);
		}
	}

	// prevents spectator joining or sets choosen amount of slots
	else if(command ~= "SPEC" || command ~= "SPECS" || command ~= "SPECTATOR" || command ~= "SPECTATORS")
	{
		if(mod ~= "DEFAULT")
		{
			KFGT.MaxSpectators = ServerSpectatorNum;
			BroadcastText("%wSpectator slots are restored to default!", true);
		}

		else if(mod ~= "OFF")
		{
			KFGT.MaxSpectators = 0;
			BroadcastText("%wSpectator slots are disabled!", true);
		}

		else
		{
			KFGT.MaxSpectators = Int(mod);
			BroadcastText("%wSpectator slots are set to - %b"$Int(mod), true);
		}
	}

	// a switch for slomo
	else if(command ~= "DRAMA" || command ~= "SLOMO")
	{
		if(mod ~= "ON")
    {
      bNoDrama = false;
      BroadcastText("%wSlomo - %b"$mod, true);
    }

		else if(mod ~= "OFF")
    {
      bNoDrama = true;
      BroadcastText("%wSlomo - %b"$mod, true);
    }
	}

	// disallow usual players to use mutate cmds
	else if(command ~= "ADMINONLY" || command ~= "ADMIN")
	{
		if(!CheckAdmin(Sender))
			return;

		if(mod ~= "ON")
		{
			bAdminOnly = true;
			BroadcastText("%wOnly admins can use commands!", true);
		}

		else if(mod ~= "OFF")
		{
			bAdminOnly = false;
			BroadcastText("%wAll players can use commands!", true);
		}
	}

	// save all changed stuff, since all other cmds dont touch the config
	else if(command ~= "SAVE")
	{
		if(!CheckAdmin(Sender))
			return;

		SaveConfig();
		SendMessage(Sender, "%rConfig is saved!");
	}

	else if(command ~= "STATUS")
	{
		SendMessage(Sender, "%rFaked Plus Mutator");
    SendMessage(Sender, "%wFakes - %b"$nFakes$"%w, Real Players - %b"$RealPlayers()$"%w, Player Slots - %b"$KFGT.MaxPlayers);
    SendMessage(Sender, "%wZeds Minimal Health - %b"$minNumPlayers);
    SendMessage(Sender, "%wSlomo disabled - %r"$bNoDrama$"%w, AdminOnly - %r"$bAdminOnly$"%w, SoloMode - %r"$bSoloMode);
    SendMessage(Sender, "%wDefault Spectator Slots - %b"$ServerSpectatorNum$"%w, Current Spectator Slots - %b"$KFGT.MaxSpectators);
	}

	// why not?
	else if(command ~= "CREDITS")
	{
    SendMessage(Sender, "%wAuthor %bNikC-%w. Special thanks to %bdkanus%w, %ba1eat0r%w, %bbIbIbI(rus)%w, %bscary ghost%w, %bPoosh%w.");
	}

  else if(command ~= "ReservedSlots" || command ~= "rs")
	{
		EditConfigSlots(Sender, mod);
	}

  else if(command ~= "ConfigFakes" || command ~= "cf")
	{
		EditConfigFakes(Sender, mod);
	}

	Super.Mutate(MutateString, Sender);
}


function EditConfigFakes(PlayerController pc, string mod)
{
  SendMessage(pc, "%wThis is meant to be used in %rCustom%w mode!");
}


function EditConfigSlots(PlayerController pc, string mod)
{
  SendMessage(pc, "%wThis is meant to be used in %rCustom%w mode!");
}

//============================== BROADCASTING ==============================
// SendMessage(pc, "message")
function SendMessage(PlayerController pc, coerce string message)
{
	if(pc == none || message == "")
		return;

	// keep WebAdmin clean and shiny
	if(pc.playerReplicationInfo.PlayerName ~= "WebAdmin" && pc.PlayerReplicationInfo.PlayerID == 0)
		message = StripFormattedString(message);
	else
		message = ParseFormattedLine(message);

	pc.teamMessage(none, message, 'FakedPlayers');
}


// BroadcastText("something",true/false)
function BroadcastText(string message, optional bool bSaveToLog)
{
	local Controller c;

	for(c = level.controllerList; c != none; c = c.nextController)
	{
		if(PlayerController(c) != none)
			SendMessage(PlayerController(c), message);
	}

	if(bSaveToLog)
	{
		// remove color codes for server log
		message = StripFormattedString(message);
		log("FakedPlayers: "$message);
	}
}


// color codes for messages
static function string ParseFormattedLine(string input)
{
	ReplaceText(input, "%r", chr(27)$chr(200)$chr(1)$chr(1));
	ReplaceText(input, "%g", chr(27)$chr(1)$chr(200)$chr(1));
	ReplaceText(input, "%b", chr(27)$chr(1)$chr(100)$chr(200));
	ReplaceText(input, "%w", chr(27)$chr(200)$chr(200)$chr(200));
	ReplaceText(input, "%y", chr(27)$chr(200)$chr(200)$chr(1));
	ReplaceText(input, "%p", chr(27)$chr(200)$chr(1)$chr(200));
	return input;
}


// remove color codes
function string StripFormattedString(string input)
{
	ReplaceText(input, "%r", "");
	ReplaceText(input, "%g", "");
	ReplaceText(input, "%b", "");
	ReplaceText(input, "%w", "");
	ReplaceText(input, "%y", "");
	ReplaceText(input, "%p", "");
	return input;
}


//=========================================================================
static function FillPlayInfo(PlayInfo PlayInfo)
{
	Super.FillPlayInfo(PlayInfo);

	PlayInfo.AddSetting("Faked Plus", "bNoDrama", "Disable SloMo", 0, 0, "check");
	PlayInfo.AddSetting("Faked Plus", "bAdminOnly", "Only Admins can use commands", 0, 0, "check");
	PlayInfo.AddSetting("Faked Plus", "bSoloMode", "Solo Mode", 0, 0, "check");
	PlayInfo.AddSetting("Faked Plus", "minNumPlayers", "Mimimal zed health", 0, 1, "Text", "4;0:6", "", False, False);
}


static function string GetDescriptionText(string SettingName)
{
	switch (SettingName)
	{
		case "bNoDrama":
			return "Enable/disable SloMo system";
		case "bAdminOnly":
			return "Only Admins can use commands";
		case "bSoloMode":
			return "Leaves only 1 avialable player slot";
		case "minNumPlayers":
			return "Force minimal health for zeds";
	}

	return Super.GetDescriptionText(SettingName);
}


//=========================================================================
defaultproperties
{
	 GroupName="KF-FakedPlus"
	 FriendlyName="Faked Plus"
	 Description="Simulate extra players for challenge. You can edit faked players amount in the config file."

	 minNumPlayers=1
	 ReservedPlayerSlots=0
	 nFakes=0
	 bSoloMode=false
	 bLockOn=false
	 bNoDrama=false
	 bAdminOnly=true
	 bUseReservedSlots=false
	 bRefreshMaxPlayers=true
}