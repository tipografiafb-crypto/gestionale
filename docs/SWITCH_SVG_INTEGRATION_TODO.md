# Ripresa Conversazione: Integrazione SVG Taglio → Switch

## Cosa è stato fatto

### ✅ Implementazione Ruby completata

I file di taglio SVG vengono ora inclusi nel payload inviato a Switch durante la **prestampa**:

```json
{
  "url": ".../api/assets/45/download",           // PNG stampa
  "filename": "UK7267-1.png",
  "cut_url": ".../api/assets/46/download",       // SVG taglio
  "cut_filename": "UK7267-1-cut.svg"
}
```

**File modificati:**
- `routes/order_items_switch.rb` - preprint singolo
- `routes/orders_api.rb` - bulk preprint

**Logica:** Se il prodotto ha un asset di tipo `cut`, viene aggiunto al payload. Altrimenti il payload è identico a prima (retrocompatibile).

---

## Prossimi passi da fare

### 1. Configurare Switch per gestire due file

Switch deve:
1. **Scaricare entrambi** gli URL dal payload (`url` e `cut_url`)
2. **Dividere** i file: `*.png` → Path Photoshop, `*-cut.svg` → Path Illustrator
3. **Reunire** i file processati usando la radice comune del nome
4. **Passarli a Illustrator** per creare il PDF finale

**Elementi Switch necessari:** Router, Configurators, Assemble

### 2. Creare script Illustrator (.jsx)

Uno script ExtendScript che:
- Riceve path PNG e SVG da Switch
- Apre SVG come base
- Posiziona PNG sopra
- Esporta come PDF combinato

---

## Domande aperte per te

1. Come vuoi che Illustrator posizioni la stampa rispetto al taglio? (centrata? allineata?)
2. Quali layer deve avere il PDF finale? (stampa, taglio, altri?)
3. Devo preparare un template dello script `.jsx`?

---

## Per ricominciare

Dì semplicemente:
> "Riprendiamo il discorso Switch + Illustrator per combinare PNG e SVG"

Oppure:
> "Prepara lo script Illustrator per combinare stampa e taglio"
