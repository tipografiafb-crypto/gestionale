# Destinazioni su Ubuntu

Il gestionale scrive le hot folder attraverso il percorso `/destinations` visto dai
container Docker. Sul server Ubuntu le condivisioni SMB devono essere montate sotto
una radice comune, normalmente `/mnt/gestionale`.

## Preparazione del server

1. Installare gli strumenti di rete e stampa:

   ```bash
   sudo apt install cifs-utils cups cups-client
   ```

2. Creare una cartella per ogni macchinario:

   ```bash
   sudo mkdir -p /mnt/gestionale/signracer
   sudo mkdir -p /mnt/gestionale/handtop
   ```

3. Salvare le credenziali SMB in un file leggibile solo da root, per esempio
   `/etc/gestionale/signracer.credentials`:

   ```text
   username=UTENTE
   password=PASSWORD
   ```

4. Aggiungere il mount a `/etc/fstab`. Esempio:

   ```text
   //192.168.1.100/hotfolder/signracer /mnt/gestionale/signracer cifs credentials=/etc/gestionale/signracer.credentials,uid=1000,gid=1000,file_mode=0664,dir_mode=0775,nofail,_netdev,x-systemd.automount 0 0
   ```

5. Impostare nel file `.env` usato da Docker Compose:

   ```text
   AUTOMATION_DESTINATIONS_HOST_ROOT=/mnt/gestionale
   ```

Il volume definito in `docker-compose.yml` rende quindi
`/mnt/gestionale/signracer` visibile nel container come
`/destinations/signracer`.

## Stampanti etichette

Configurare su CUPS di Ubuntu una coda per ogni Brother QL-810W, con nomi stabili
come `signracer` e `handtop`. Il container usa il server CUPS indicato nella
destinazione, normalmente `host.docker.internal:631`.

CUPS deve accettare le richieste provenienti dalla rete bridge Docker. La
configurazione dipende dalla rete assegnata da Docker; limitare l’accesso alla sola
subnet dei container e non esporre CUPS su Internet.

La funzione **Verifica senza inviare file** controlla soltanto che la cartella sia
scrivibile o che la coda CUPS esista. La prima stampa fisica avviene esclusivamente
quando un flusso reale raggiunge il blocco **Stampa etichetta**.
