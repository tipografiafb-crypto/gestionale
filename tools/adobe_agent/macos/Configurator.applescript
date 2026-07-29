use scripting additions

on run
	display dialog "Questa procedura collega il Mac al gestionale e configura Photoshop e Illustrator. Non serve usare il Terminale." buttons {"Annulla", "Inizia"} default button "Inizia"
	
	set serverDialog to display dialog "1 di 4 — Indirizzo del gestionale nella rete locale:" default answer "http://192.168.1.75:5010" buttons {"Annulla", "Continua"} default button "Continua"
	set serverURL to text returned of serverDialog
	
	set codeDialog to display dialog "2 di 4 — Inserisci il codice temporaneo mostrato in Automazioni → Macchine Adobe:" default answer "" buttons {"Annulla", "Continua"} default button "Continua"
	set pairingCode to text returned of codeDialog
	
	set defaultName to computer name of (system info)
	set nameDialog to display dialog "3 di 4 — Come vuoi chiamare questo Mac nel gestionale?" default answer defaultName buttons {"Annulla", "Continua"} default button "Continua"
	set machineName to text returned of nameDialog
	
	set photoshopApps to my adobeApplications("Adobe Photoshop")
	if (count of photoshopApps) is 0 then
		display dialog "Non è stata trovata alcuna versione di Adobe Photoshop nella cartella Applicazioni." buttons {"Chiudi"} default button "Chiudi"
		return
	end if
	set selectedPhotoshop to choose from list photoshopApps with title "4 di 4 — Applicazioni Adobe" with prompt "Scegli Photoshop. Per il flusso attuale usa Photoshop 2024." default items {my preferredApplication(photoshopApps, "2024")}
	if selectedPhotoshop is false then return
	
	set illustratorApps to my adobeApplications("Adobe Illustrator")
	if (count of illustratorApps) is 0 then
		display dialog "Non è stata trovata alcuna versione di Adobe Illustrator nella cartella Applicazioni." buttons {"Chiudi"} default button "Chiudi"
		return
	end if
	set selectedIllustrator to choose from list illustratorApps with title "4 di 4 — Applicazioni Adobe" with prompt "Scegli Illustrator." default items {item 1 of illustratorApps}
	if selectedIllustrator is false then return
	
	set summaryText to "Gestionale: " & serverURL & return & "Mac: " & machineName & return & "Photoshop: " & item 1 of selectedPhotoshop & return & "Illustrator: " & item 1 of selectedIllustrator & return & return & "Verranno create automaticamente le cartelle condivise in /Users/Shared/MagentaAdobe."
	display dialog "Conferma configurazione" & return & return & summaryText buttons {"Indietro", "Collega e avvia"} default button "Collega e avvia"
	
	try
		set helperPath to POSIX path of (path to resource "adobe_agent.py")
		set commandText to "/usr/bin/python3 " & quoted form of helperPath & " --server " & quoted form of serverURL & " --name " & quoted form of machineName & " --photoshop-app " & quoted form of (item 1 of selectedPhotoshop) & " --illustrator-app " & quoted form of (item 1 of selectedIllustrator) & " --template-root " & quoted form of "/Users/Shared/MagentaAdobe/illustrator/templates" & " --script-root " & quoted form of "/Users/Shared/MagentaAdobe/illustrator/scripts" & " --pair " & quoted form of pairingCode & " --install-service"
		do shell script commandText
		set testDialog to display dialog "Configurazione completata." & return & return & "Il Mac è collegato e Magenta Adobe Agent è in esecuzione. Vuoi aprire Photoshop e sincronizzare adesso l’elenco delle azioni?" buttons {"Più tardi", "Controlla Photoshop"} default button "Controlla Photoshop"
		if button returned of testDialog is "Controlla Photoshop" then
			try
				set scanResult to do shell script "/usr/bin/python3 " & quoted form of helperPath & " --scan-photoshop-actions"
				display dialog scanResult buttons {"Continua"} default button "Continua"
			on error scanError
				display dialog "Il Mac è collegato, ma il controllo Photoshop non è riuscito:" & return & return & scanError & return & return & "Puoi ripeterlo in seguito dopo aver autorizzato il controllo di Photoshop nelle impostazioni di macOS." buttons {"Continua"} default button "Continua"
			end try
		end if
		set folderDialog to display dialog "Ora torna alla pagina Macchine Adobe del gestionale. Le maschere e gli script possono essere copiati nella cartella risorse condivisa." buttons {"Fine", "Apri cartella risorse"} default button "Fine"
		if button returned of folderDialog is "Apri cartella risorse" then
			tell application "Finder" to open POSIX file "/Users/Shared/MagentaAdobe"
		end if
	on error errorMessage
		display dialog "Configurazione non completata:" & return & return & errorMessage & return & return & "Controlla l’indirizzo, genera un nuovo codice e riprova." buttons {"Chiudi"} default button "Chiudi"
	end try
end run

on adobeApplications(applicationPrefix)
	set applicationNames to {}
	tell application "Finder"
		set matchingApplications to every item of folder "Applications" of startup disk whose name starts with applicationPrefix and name ends with ".app"
		repeat with applicationItem in matchingApplications
			set end of applicationNames to text 1 thru -5 of (name of applicationItem as text)
		end repeat
	end tell
	return applicationNames
end adobeApplications

on preferredApplication(applicationNames, versionText)
	repeat with applicationName in applicationNames
		if (applicationName as text) contains versionText then return applicationName as text
	end repeat
	return item 1 of applicationNames
end preferredApplication
