# Galicia Local - Project Plan

## Concept
Een doorzoekbare database van diensten en bedrijven in Galicië, specifiek gericht op:
- Expats en nieuwkomers (Engels/Nederlands/Duits sprekend)
- Toeristen die "local" willen ervaren
- Mensen die naar Galicië willen verhuizen

## Waarom dit project?
- Strategische waarde voor FocusTime retreats
- Persoonlijke connectie met de regio (toekomstige woonplek)
- Netwerk opbouwen bij lokale dienstverleners
- Geen goede gestructureerde data beschikbaar (alleen blogposts en incomplete directories)

---

## Categorieën

### Prioriteit 1: Expat Essentials
| Categorie | Voorbeelden | Data bronnen |
|-----------|-------------|--------------|
| **Professionals die Engels spreken** | Advocaten, accountants, notarissen | LinkedIn, lokale kamers van koophandel |
| **Makelaars** | Inmobiliarias met internationale ervaring | Idealista, Fotocasa, lokale websites |
| **Medisch** | Huisartsen, tandartsen, ziekenhuizen | Google Maps, Sergas (Galicische gezondheidszorg) |
| **Scholen** | Internationale scholen, taalscholen | Xunta de Galicia onderwijs register |

### Prioriteit 2: Dagelijks leven
| Categorie | Voorbeelden | Data bronnen |
|-----------|-------------|--------------|
| **Supermarkten** | Mercadona, Froiz, Gadis, lokale winkels | Google Maps, OpenStreetMap |
| **Markten** | Wekelijkse mercados, waar en wanneer | Gemeente websites, Facebook events |
| **Bakkers & slagers** | Lokale panaderías, carnicerías | Google Maps, lokale gidsen |
| **Kappers** | Peluquerías | Google Maps |

### Prioriteit 3: Lifestyle & Cultuur
| Categorie | Voorbeelden | Data bronnen |
|-----------|-------------|--------------|
| **Bodegas** | Wijnhuizen met bezoek mogelijkheid | Ruta do Viño websites, enoturismospain.com |
| **Restaurants** | Focus op lokale/authentieke plekken | TripAdvisor, Google Maps, lokale blogs |
| **Sidrerías** | Cider houses | Lokale gidsen |
| **Festivals** | Romerías, ferias, fiestas | Gemeente kalenders |

### Prioriteit 4: Praktisch
| Categorie | Voorbeelden | Data bronnen |
|-----------|-------------|--------------|
| **Handwerk** | Loodgieters, elektriciens, aannemers | Páginas Amarillas, Google Maps |
| **Auto** | Garages, ITV (APK) stations | Google Maps |
| **Huisdieren** | Dierenartsen, pet shops | Google Maps |

---

## Scraping + LLM Pipeline

### Stap 1: Data verzamelen (Scraping)

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  Google Maps    │     │  Páginas        │     │  Gemeente       │
│  Places API     │     │  Amarillas      │     │  Websites       │
└────────┬────────┘     └────────┬────────┘     └────────┬────────┘
         │                       │                       │
         └───────────────────────┴───────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │   Raw Data Storage     │
                    │   (PostgreSQL/JSON)    │
                    └────────────────────────┘
```

**Bronnen om te scrapen:**
1. **Google Maps/Places API** - Basisgegevens, reviews, openingstijden
2. **Páginas Amarillas** - Spaanse Gouden Gids
3. **Gemeente websites** - Evenementen, markten, officiële info
4. **Facebook Pages** - Lokale bedrijven zonder website
5. **TripAdvisor** - Reviews en ratings
6. **LinkedIn** - Professionals met taleninfo

### Stap 2: Data verrijken (LLM)

```
┌────────────────────────┐
│   Raw scraped data     │
│   - Naam               │
│   - Adres              │
│   - Telefoon           │
│   - Reviews (Spaans)   │
└────────────┬───────────┘
             │
             ▼
┌────────────────────────────────────────────────────────┐
│                    LLM Processing                       │
│                                                         │
│  1. Taaldetectie: Spreekt eigenaar Engels/Nederlands?  │
│     - Analyseer reviews voor mentions van taal         │
│     - Check website voor taalopties                    │
│                                                         │
│  2. Categorisatie: Welke subcategorieën?               │
│     - "Advocaat" → Immigratie? Vastgoed? Algemeen?     │
│                                                         │
│  3. Samenvatting: Wat maakt deze plek bijzonder?       │
│     - Genereer korte beschrijving uit reviews          │
│                                                         │
│  4. Vertaling: Spaanse content → Engels/Nederlands     │
│     - Beschrijvingen                                   │
│     - Belangrijke reviews                              │
│                                                         │
│  5. Kwaliteitsscore: Hoe betrouwbaar is deze data?     │
│     - Recente reviews? Actieve website? Telefoon werkt?│
└────────────────────────────────────────────────────────┘
             │
             ▼
┌────────────────────────┐
│   Enriched Data        │
│   - Basis info         │
│   - Talen: [EN, ES]    │
│   - Categorie: exact   │
│   - AI samenvatting    │
│   - Kwaliteitsscore    │
└────────────────────────┘
```

### Stap 3: Continue updates

```
┌─────────────────────────────────────────────────────────┐
│                   Update Pipeline                        │
│                                                          │
│  Dagelijks:                                              │
│  - Check of websites nog werken                          │
│  - Monitor Google Maps voor gewijzigde openingstijden    │
│                                                          │
│  Wekelijks:                                              │
│  - Scrape nieuwe reviews                                 │
│  - LLM: update samenvattingen als nodig                  │
│  - Detecteer nieuwe bedrijven in gebied                  │
│                                                          │
│  User feedback:                                          │
│  - "Dit klopt niet meer" button                          │
│  - Community corrections                                 │
└─────────────────────────────────────────────────────────┘
```

---

## LLM Use Cases - Specifiek

### 1. Taaldetectie uit reviews
```
Input (Spaanse review):
"Muy profesional, habla inglés perfectamente.
Me ayudó con todo el papeleo de mi residencia."

LLM Output:
{
  "speaks_english": true,
  "confidence": 0.95,
  "evidence": "Review mentions 'habla inglés perfectamente'"
}
```

### 2. Automatische categorisatie
```
Input:
Business name: "García & Asociados Abogados"
Description: "Especialistas en derecho inmobiliario y extranjería"

LLM Output:
{
  "primary_category": "lawyer",
  "subcategories": ["real_estate", "immigration"],
  "relevant_for_expats": true
}
```

### 3. Review samenvatting
```
Input: 47 Google reviews in het Spaans

LLM Output:
{
  "summary_en": "Family-run bakery known for empanadas and
                traditional Galician bread. Locals recommend
                arriving before 10am for fresh items.",
  "highlights": ["empanadas", "early morning best"],
  "warnings": ["closed Mondays", "cash only"]
}
```

### 4. Openingstijden extractie
```
Input (van website scrape):
"Abrimos de lunes a viernes de 9:00 a 14:00 y de 17:00 a 20:00.
Sábados solo mañanas. Domingos cerrado."

LLM Output:
{
  "hours": {
    "monday": "09:00-14:00, 17:00-20:00",
    "tuesday": "09:00-14:00, 17:00-20:00",
    ...
    "saturday": "09:00-14:00",
    "sunday": "closed"
  }
}
```

---

## Naam suggesties

| Naam | Uitleg |
|------|--------|
| **GaliciaLocal** | Simpel, duidelijk |
| **VivirGalicia** | "Leven in Galicië" |
| **MiGalicia** | "Mijn Galicië" - persoonlijk |
| **GaliciaGuide** | Engels, breed publiek |
| **Morriña** | Galicisch woord voor heimwee/verlangen - poëtisch |
| **TerraMeiga** | "Betoverd land" - Galicische uitdrukking |
| **RíasLocales** | Verwijzing naar de beroemde rías |

**Mijn voorkeur:** `GaliciaLocal.com` of `VivirGalicia.com`
- Duidelijk wat het is
- Makkelijk te onthouden
- Domain waarschijnlijk beschikbaar

---

## Tech Stack (Past bij jouw skills)

- **Backend**: Phoenix/Elixir (wat je al kent)
- **Database**: PostgreSQL met PostGIS voor geo queries
- **Scraping**:
  - Elixir: Crawly of custom GenServer workers
  - Python: Scrapy voor complexe sites (optioneel)
- **LLM**:
  - Claude API voor verrijking
  - Lokaal model (Ollama) voor bulk processing
- **Frontend**: LiveView met kaart (Leaflet/MapLibre)
- **Search**: PostgreSQL full-text of MeiliSearch

---

## MVP Scope

### Fase 1: Proof of Concept
- [ ] 1 stad (bijv. Santiago de Compostela)
- [ ] 3 categorieën: Restaurants, Makelaars, Medisch
- [ ] Google Maps data scrapen
- [ ] LLM verrijking voor taalinfo
- [ ] Simpele kaart + lijst view

### Fase 2: Uitbreiding
- [ ] Alle 4 provincies
- [ ] Alle categorieën
- [ ] User submissions
- [ ] "Spreekt Engels" filter

### Fase 3: Community
- [ ] User reviews/corrections
- [ ] Claim your business
- [ ] Premium listings (revenue)

---

## Waarom dit WEL werken kan (ondanks kleine markt)

1. **Jij bent de doelgroep** - Je weet precies wat expats nodig hebben
2. **FocusTime synergie** - Retreat gasten krijgen toegang, jij leert de regio
3. **Netwerk effect** - Elke listing is een potentiële zakelijke relatie
4. **SEO lange termijn** - "English speaking lawyer Galicia" etc.
5. **Eventueel: andere regio's** - Model kan naar Algarve, Costa Blanca, etc.

---

## Volgende stappen

1. **Domain checken**: galicialocal.com, vivirgalicia.com
2. **Google Maps API**: Quota en kosten checken
3. **Eerste scrape**: 100 businesses in Santiago
4. **LLM experiment**: Taaldetectie accuracy testen
5. **Simpele UI**: Kaart + filters prototype

---

*Laatste update: 28 januari 2026*
