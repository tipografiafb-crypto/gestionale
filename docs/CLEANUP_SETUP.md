# Storage Cleanup - Uso manuale

La pulizia non è schedulata: si avvia dalla pagina `/admin/cleanup` oppure tramite script. In produzione la retention configurata è di 45 giorni (`DAYS_TO_KEEP=45`).

La pulizia per retention scansiona tutta la cartella `storage` e include i file grafici scaricati e quelli elaborati più vecchi della stessa soglia, inclusi i PDF finali e quelli referenziati. Quando un file viene rimosso, gli eventuali record `Asset` vengono marcati come eliminati e gli `AutomationArtifact` associati vengono rimossi. I file non grafici (per esempio JSON di contesto) sono conservati.

## Anteprima dalla pagina

1. Apri `/admin/cleanup`.
2. Clicca **Test (anteprima senza cancellare)** per vedere quanti file e quanto spazio sarebbero rimossi.
3. Clicca **Esegui Pulizia (CANCELLA)** solo quando vuoi applicare la pulizia.

## Script

Anteprima senza cancellare:

```bash
bundle exec ruby scripts/cleanup.rb --dry-run
```

Esecuzione manuale:

```bash
bundle exec ruby scripts/cleanup.rb
```

Per cambiare la retention solo per una singola esecuzione si può passare `--days=N`.

## Sicurezza

- Gli asset vengono gestiti secondo la data di importazione e il flag `deleted_at`.
- Tutti i file grafici sotto `storage` (PDF, immagini e formati di grafica) sono candidati in base alla data di modifica del file.
- Anche i file finali referenziati vengono rimossi alla scadenza; i record asset e artifact associati vengono aggiornati o rimossi dal database.
- I file non grafici sotto `storage` sono conservati.
- L'anteprima `--dry-run` non cancella file.
