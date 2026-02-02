🔄 SISTEMA RECOVERY + [tuo problema]
Esempio concreto:

🔄 SISTEMA RECOVERY: Il checkout non funziona quando aggiungo prodotti personalizzati al carrello
Cosa succede automaticamente:

📋 Recovery Completo → Leggo tutto replit.md + tutti i file System program/
🔍 Analisi Globale → Non so ancora quale feature, quindi esploro tutto
🎯 Identificazione Automatica → Analizzo il problema e identifico che tocca: cart + checkout + export
📊 Health Check → Controllo SYSTEM_STATUS.md per problemi noti
🧪 Diagnosi Completa → HOOKS.md, EVENTS.md, DEPS.md per capire cosa è rotto
🛠️ Risoluzione Multipla → Potrei toccare più features per risolvere
Quando usarlo: Quando non sai quale feature tocca il problema o sospetti che sia complesso/multi-feature.

🎯 RICHIESTA CHIRURGICA + Feature Target: [feature] + [problema]
Esempio concreto:

🎯 RICHIESTA CHIRURGICA + Feature Target: canvas + L'editor non salva le modifiche quando ruoto le immagini
Cosa succede automaticamente:

🎯 Targeting Preciso → Vado diretto su feature "canvas"
📋 Scope Verification → Controllo System program/scope/canvas.allow per file permessi
🔍 Moduli Canvas → Leggo MODULES.md filtrando solo moduli canvas
🔗 Hook Canvas → HOOKS.md per hook specifici canvas
📝 Template Chirurgico → Uso template da PROMPTS.md per modifiche precise
🧪 Contract Tests → Eseguo tests/contracts/CanvasEngineContract.test.js
⚡ Risoluzione Focalizzata → Modifico SOLO moduli canvas autorizzati
Quando usarlo: Quando sai esattamente quale feature ha il problema e vuoi massima precisione.

🛠️ FEATURE TARGET: [feature] + [problema]
Esempio concreto:

🛠️ FEATURE TARGET: ai + Le immagini AI generate hanno qualità troppo bassa
Cosa succede automaticamente:

⚡ Targeting Immediato → Salto recovery, vado diretto su feature "ai"
📋 Quick Scope → Controllo veloce scope/ai.allow
🎯 Moduli AI Only → MODULES.md filtrando solo feature "ai"
🔧 Fix Rapido → Uso pattern standard senza template complessi
✅ Verifica Minima → Controlli essenziali di sicurezza
Quando usarlo: Quando il problema è semplice, ben definito, e sei sicuro della feature target.

📊 Confronto Pratico
Situazione	Comando Consigliato	Tempo	Precisione
"Il plugin è rotto"	🔄 SISTEMA RECOVERY	⏱️ Lento	🎯 Massima
"Canvas non salva"	🎯 RICHIESTA CHIRURGICA	⏱️ Medio	🎯 Alta
"Cambia colore bottone AI"	🛠️ FEATURE TARGET	⏱️ Veloce	🎯 Sufficiente
💡 Esempi di Utilizzo Reali
Recovery completo:

🔄 SISTEMA RECOVERY: Dopo l'ultimo aggiornamento, nessun customizer si apre più
Chirurgico preciso:

🎯 RICHIESTA CHIRURGICA + Feature Target: export + Gli HD print escono sfocati
Targeting rapido:

🛠️ FEATURE TARGET: ui + Il pannello layers è troppo stretto su mobile
Ogni comando attiva automaticamente tutti i controlli di sicurezza e compliance, ma con diversi livelli di approfondimento!