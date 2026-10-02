extends SceneTree

const ItemPresentationScript := preload("res://ui/item_presentation.gd")

var failures := 0

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	TranslationServer.set_locale("sv")
	_check(str(TranslationServer.translate("RUN OVER")) == "RUNDAN ÄR SLUT", "Swedish run-over translation should load")
	_check(str(TranslationServer.translate("New Game")) == "Nytt spel", "Swedish menu translation should load")
	_check(str(TranslationServer.translate("GAME HUB")) == "SPEL", "Swedish game hub translation should load")
	_check(str(TranslationServer.translate("Start run")) == "Starta runda", "Swedish run action should load")
	_check(str(TranslationServer.translate("Character / Inventory")) == "Karaktär / väska", "Swedish inventory action should load")
	_check(str(TranslationServer.translate("Bag · 24 slots per page")) == "Väska · 24 platser per sida", "Swedish inventory grid label should load")
	_check(str(TranslationServer.translate("Coins: %d") % 250) == "Mynt: 250", "Swedish wallet label should load")
	_check(str(TranslationServer.translate("Join challenge")) == "Gå med i utmaning", "Swedish challenge menu option should load")
	_check(str(TranslationServer.translate("JOIN CHALLENGE")) == "GÅ MED I UTMANING", "Swedish challenge heading should load")
	_check(str(TranslationServer.translate("MY CHALLENGES")) == "MINA UTMANINGAR", "Swedish saved-challenges heading should load")
	_check(str(TranslationServer.translate("Give your challenge a name")) == "Ge utmaningen ett namn", "Swedish challenge-name prompt should load")
	_check(str(TranslationServer.translate("Remove from my list")) == "Ta bort från min lista", "Swedish saved-challenge removal action should load")
	_check(str(TranslationServer.translate("Copy challenge code")) == "Kopiera utmaningskod", "Swedish challenge-code copy action should load")
	_check(str(TranslationServer.translate("Challenge code copied. Share it with a friend!")) == "Utmaningskoden är kopierad. Dela den med en vän!", "Swedish copied-code feedback should load")
	_check(str(TranslationServer.translate("Difficulty: %s") % TranslationServer.translate("Normal")) == "Svårighetsgrad: Normal", "Swedish challenge difficulty summary should load")
	_check(str(TranslationServer.translate("Continue with email")) == "Fortsätt med e-post", "Swedish email account option should load")
	_check(str(TranslationServer.translate("RACE RESULTS")) == "LOPPRESULTAT", "Swedish multiplayer results heading should load")
	_check(str(TranslationServer.translate("Return to lobby")) == "Tillbaka till lobbyn", "Swedish multiplayer lobby return action should load")
	_check(str(TranslationServer.translate("Next skin")) == "Nästa utseende", "Swedish lobby skin selector label should load")
	_check(str(TranslationServer.translate("Email account")) == "E-postkonto", "Swedish email account view title should load")
	_check(str(TranslationServer.translate("Single runs")) == "Enskilda rundor", "Swedish single-run leaderboard option should load")
	_check(str(TranslationServer.translate("Total distance")) == "Total distans", "Swedish total-distance leaderboard option should load")
	_check(str(TranslationServer.translate("This month")) == "Den här månaden", "Swedish monthly leaderboard option should load")
	_check(str(TranslationServer.translate("Save score to this seed")) == "Spara resultat på den här banan", "Swedish seed-score action should load")
	_check(str(TranslationServer.translate("YOU")) == "DU", "Swedish chase marker should load")
	_check(str(TranslationServer.translate("NEXT: %s · %d m") % ["Yellmen", 250]) == "NÄSTA: Yellmen · 250 m", "Swedish seed chase target should load")
	_check(str(TranslationServer.translate("Your nickname and result on this seed will be public.")) == "Ditt nickname och resultat på den här banan visas offentligt.", "Seed-result visibility should be disclosed in Swedish")
	_check(str(TranslationServer.translate("THIS MONTH — TOP 20")) == "DEN HÄR MÅNADEN — TOPP 20", "Swedish monthly leaderboard title should load")
	_check(str(TranslationServer.translate("BANK  %d") % 123) == "BANK  123", "Swedish account wallet HUD label should load")
	_check(str(TranslationServer.translate("Sign in to save coins and total distance.")) == "Logga in för att spara mynt och total distans.", "Swedish guest account-progress hint should load")
	_check(str(TranslationServer.translate("Music volume")) == "Musikvolym", "Swedish music volume label should load")
	_check(str(TranslationServer.translate("Equip")) == "Utrusta" and str(TranslationServer.translate("Unequip")) == "Ta av", "Swedish equipment actions should load")
	_check(str(TranslationServer.translate("item.boots_canvas_01.name")) == "Lärkor", "Swedish symbolic item name should load")
	_check(str(TranslationServer.translate("item.boots_canvas_01.description")) == "Bekväma skor av tyg.", "Swedish item description should omit catalog-driven modifiers")
	TranslationServer.set_locale("en")
	_check(str(TranslationServer.translate("RUN OVER")) == "RUN OVER", "English should use the source text")
	_check(str(TranslationServer.translate("item.boots_canvas_01.name")) == "Canvas Boots", "English symbolic item name should load")
	_check(str(TranslationServer.translate("item.helmet_scout_01.description")) == "A light hood for quick expeditions.", "English symbolic item description should load")
	if failures == 0:
		print("Localization tests passed.")
	quit(1 if failures > 0 else 0)

func _check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
