defmodule GaliciaLocal.Repo.Migrations.SeedNewCategoriesAndEnrichmentHints do
  use Ecto.Migration

  def up do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # ── 1. Create new categories ──────────────────────────────────────────

    new_categories = [
      %{
        slug: "music-schools",
        name: "Music Schools",
        description: "Music lessons and instrument training",
        icon: "musical-note",
        priority: 3,
        search_queries: ["music school", "music lessons", "music academy", "instrument lessons"],
        enrichment_hints: "Note what instruments and styles are taught. Mention if they offer group classes, private lessons, or both. Note age groups served."
      },
      %{
        slug: "elementary-schools",
        name: "Elementary Schools",
        description: "Primary education for children ages 4-12",
        icon: "academic-cap",
        priority: 1,
        search_queries: ["elementary school", "primary school"],
        enrichment_hints: "Note whether this is a public, semi-private, or private school. Mention the language of instruction and whether they offer support for non-native speaking children."
      },
      %{
        slug: "high-schools",
        name: "High Schools",
        description: "Secondary education for teenagers",
        icon: "academic-cap",
        priority: 1,
        search_queries: ["high school", "secondary school"],
        enrichment_hints: "Note the school type and tracks available. Mention any special programs, international baccalaureate, or bilingual education options."
      },
      %{
        slug: "libraries",
        name: "Libraries",
        description: "Public libraries and reading spaces",
        icon: "book-open",
        priority: 2,
        search_queries: ["library", "public library"],
        enrichment_hints: "Note opening hours and services beyond lending books: internet access, cultural events, language courses, community spaces."
      },
      %{
        slug: "municipalities",
        name: "Municipalities",
        description: "Local government offices for registration and civil matters",
        icon: "building-library",
        priority: 1,
        search_queries: ["municipality", "town hall", "city hall"],
        enrichment_hints: "Note office hours and whether appointments are required. Mention key services for newcomers: resident registration, ID procedures, civil registry."
      },
      %{
        slug: "hospitals",
        name: "Hospitals",
        description: "Hospitals and emergency medical facilities",
        icon: "heart",
        priority: 1,
        search_queries: ["hospital", "emergency room", "medical center"],
        enrichment_hints: "Note whether this is a public or private hospital. Mention emergency room availability, main specialties, and what documentation is needed for treatment."
      }
    ]

    for cat <- new_categories do
      execute """
      INSERT INTO categories (id, name, slug, description, icon, priority, search_queries, enrichment_hints, inserted_at, updated_at)
      VALUES (
        gen_random_uuid(),
        '#{esc(cat.name)}',
        '#{cat.slug}',
        '#{esc(cat.description)}',
        '#{cat.icon}',
        #{cat.priority},
        #{pg_array(cat.search_queries)},
        '#{esc(cat.enrichment_hints)}',
        '#{now}',
        '#{now}'
      )
      """
    end

    # ── 2. Create translations for new categories ─────────────────────────

    new_translations = [
      # Music Schools
      {"music-schools", "en", "Music Schools", "Music lessons and instrument training", "music school",
        ["music school", "music lessons", "music academy"], nil},
      {"music-schools", "es", "Escuelas de Música", "Clases de música y formación instrumental", "escuela de musica",
        ["escuela de música", "academia de música", "clases de música", "conservatorio"],
        "In Galicia, note if they teach traditional Galician instruments like gaita (Galician bagpipe), pandeireta (tambourine), or zanfona (hurdy-gurdy). The conservatorio is the formal music school system. Note if they participate in romerías or folk festivals."},
      {"music-schools", "nl", "Muziekscholen", "Muzieklessen en instrumentale opleiding", "muziekschool",
        ["muziekschool", "muziekles", "muziekacademie", "conservatorium"],
        "Dutch muziekscholen often operate within a cultureel centrum. Note if they offer instrumental lessons, ensemble playing, or music theory. Many towns have a harmonie or fanfare (brass band) tradition. Note if they accept cultuurbonnen or have youth programs (jeugdmuziekschool)."},

      # Elementary Schools
      {"elementary-schools", "en", "Elementary Schools", "Primary education for children ages 4-12", "elementary school",
        ["elementary school", "primary school"], nil},
      {"elementary-schools", "es", "Colegios de Primaria", "Educación primaria para niños de 3 a 12 años", "colegio primaria",
        ["colegio", "colegio público", "CEIP", "escuela primaria", "colegio concertado"],
        "Spanish primary education (educación primaria) is for ages 6-12, with infantil for 3-6. Note if this is a public (CEIP/colegio público), concertado (semi-private), or private school. Galician is mandatory alongside Spanish in Galicia. Note if they have an aula de acogida (welcome classroom) for non-Spanish speaking children."},
      {"elementary-schools", "nl", "Basisscholen", "Basisonderwijs voor kinderen van 4 tot 12 jaar", "basisschool",
        ["basisschool", "openbare school", "montessorischool", "daltonschool"],
        "Dutch basisschool covers ages 4-12. Note the school concept: Montessori, Dalton, Jenaplan, Vrije School (Waldorf), or regulier. Mention if openbaar (public/secular) or bijzonder (religious/philosophical). Note if they have a nieuwkomersklas or schakelklas for children who don't yet speak Dutch. The schooladvies in group 8 determines secondary school level."},

      # High Schools
      {"high-schools", "en", "High Schools", "Secondary education for teenagers", "high school",
        ["high school", "secondary school"], nil},
      {"high-schools", "es", "Institutos de Secundaria", "Educación secundaria para adolescentes", "instituto secundaria",
        ["instituto", "IES", "instituto educación secundaria", "bachillerato"],
        "Spanish secondary education: ESO (12-16, compulsory) and Bachillerato (16-18, pre-university). Note if this is a public IES (Instituto de Educación Secundaria), concertado, or private. Mention available bachillerato modalities (ciencias, humanidades y ciencias sociales, artes). Note if they offer FP (Formación Profesional/vocational training)."},
      {"high-schools", "nl", "Middelbare Scholen", "Voortgezet onderwijs voor tieners", "middelbare school",
        ["middelbare school", "voortgezet onderwijs", "scholengemeenschap", "lyceum", "gymnasium"],
        "Dutch secondary education has multiple tracks: vmbo (4 years, vocational), havo (5 years, applied), vwo/gymnasium (6 years, pre-university). Note which tracks this school offers. An ISK (Internationale Schakelklas) helps newcomer teens learn Dutch before regular education. Mention if they offer tweetalig onderwijs (bilingual education) or technasium programs."},

      # Libraries
      {"libraries", "en", "Libraries", "Public libraries and reading spaces", "library",
        ["library", "public library"], nil},
      {"libraries", "es", "Bibliotecas", "Bibliotecas públicas y espacios de lectura", "biblioteca",
        ["biblioteca", "biblioteca pública", "biblioteca municipal"],
        "Galician libraries (bibliotecas) often host cultural events, language exchanges (intercambios), and offer free internet access. Note opening hours (may close for lunch). Some offer Spanish/Galician language courses for foreigners. The Red de Bibliotecas de Galicia connects the system. Mention if they have a multilingual collection."},
      {"libraries", "nl", "Bibliotheken", "Openbare bibliotheken en leesruimtes", "bibliotheek",
        ["bibliotheek", "openbare bibliotheek"],
        "Dutch libraries (bibliotheken) are community hubs: language cafes (taalhuis/taalcafé) for learning Dutch, computer access, cultural events, and children's programs. Many offer a free introduction for newcomers. Note if they have a Taalhuis (language house) for Dutch learners, as this is hugely valuable for newcomers. Membership is typically around 50-60 euro per year."},

      # Municipalities
      {"municipalities", "en", "Municipalities", "Local government offices for registration and civil matters", "municipality",
        ["municipality", "town hall", "city hall"], nil},
      {"municipalities", "es", "Concellos", "Oficinas de gobierno local para registro y trámites civiles", "concello",
        ["concello", "ayuntamiento", "oficina municipal", "registro civil"],
        "The concello (ayuntamiento in standard Spanish) handles empadronamiento (municipal registration), which is essential for accessing healthcare, schools, and starting the NIE/residency process. Note office hours (often limited, cita previa may be required). Mention if they have an oficina de atención al ciudadano or oficina de estranxeiría for foreigners."},
      {"municipalities", "nl", "Gemeenten", "Lokale overheidsinstanties voor registratie en burgerlijke zaken", "gemeente",
        ["gemeente", "gemeentehuis", "stadhuis", "burgerzaken"],
        "The gemeente is the first stop for newcomers: you must register within 5 days of arrival to get a BSN (burgerservicenummer), needed for everything: bank account, work, healthcare, and housing. Note office locations and whether you need an afspraak (appointment, usually required). Key services: inschrijving BRP, paspoort, rijbewijs, verhuizing doorgeven."},

      # Hospitals
      {"hospitals", "en", "Hospitals", "Hospitals and emergency medical facilities", "hospital",
        ["hospital", "emergency room", "medical center"], nil},
      {"hospitals", "es", "Hospitales", "Hospitales y servicios médicos de urgencias", "hospital",
        ["hospital", "urgencias", "complejo hospitalario", "centro médico"],
        "SERGAS is Galicia's public healthcare system. Note if this is a public hospital (complexo hospitalario), private hospital, or clinic. Mention urgencias (ER) availability and hours. For public hospitals, a tarjeta sanitaria is required. Mention the PAC (Punto de Atención Continuada) for after-hours urgent care. Note main specialties."},
      {"hospitals", "nl", "Ziekenhuizen", "Ziekenhuizen en spoedeisende hulp", "ziekenhuis",
        ["ziekenhuis", "spoedeisende hulp", "medisch centrum", "SEH"],
        "In the Netherlands, hospitals are accessed through a huisarts referral (except spoedeisende hulp/ER). Note if this is a general hospital (algemeen ziekenhuis), academic hospital (UMC), or specialized clinic. The SEH (spoedeisende hulp) is the ER. Mention if there's a huisartsenpost (GP after-hours clinic) on site. Dutch healthcare requires basisverzekering (basic health insurance)."}
    ]

    for {slug, locale, name, desc, search_trans, search_q, hints} <- new_translations do
      hints_sql = if hints, do: "'#{esc(hints)}'", else: "NULL"

      execute """
      INSERT INTO category_translations (id, category_id, locale, name, description, search_translation, search_queries, enrichment_hints, inserted_at, updated_at)
      VALUES (
        gen_random_uuid(),
        (SELECT id FROM categories WHERE slug = '#{slug}'),
        '#{locale}',
        '#{esc(name)}',
        '#{esc(desc)}',
        '#{esc(search_trans)}',
        #{pg_array(search_q)},
        #{hints_sql},
        '#{now}',
        '#{now}'
      )
      """
    end

    # ── 3. Add enrichment_hints to existing category translations ─────────

    existing_hints = [
      # Accountants
      {"accountants", "es",
        "In Spain, autonomous workers (autónomos) need a gestoría or asesoría for tax filing. Note if they handle autónomo registration, modelo 720 (foreign assets declaration), and non-resident tax matters. Mention if they speak English or other languages."},
      {"accountants", "nl",
        "In the Netherlands, expats may qualify for the 30% ruling (30%-regeling) tax benefit. Note if they handle expat tax returns, BTW (VAT) for ZZP'ers (freelancers), and international tax matters. The Dutch tax system (Belastingdienst) has specific rules for newcomers."},

      # Bakeries
      {"bakeries", "es",
        "Galicia has distinct bread traditions: pan de cea (DOP), bolla, empanada. Note if they make traditional Galician breads vs standard Spanish. Mention specialty items like rosca, pan de maíz (corn bread), or torta de Santiago. Many panaderías also sell empanadas."},
      {"bakeries", "nl",
        "Dutch bakeries (bakkerijen) are different from Southern European ones. Note if they sell traditional Dutch items like stroopwafels, ontbijtkoek, gevulde koeken, tompouces, or roggebrood. Many Turkish and Moroccan bakeries also sell excellent bread. Note if they bake on-site (ambachtelijk)."},

      # Butchers
      {"butchers", "es",
        "Galicia is famous for its beef (ternera gallega, rubia gallega) and pork products (lacón, chorizos, androlla). Note if they sell local breeds, cured meats (embutidos gallegos), or specialties like zorza, oreja. Mention if they make their own charcuterie."},
      {"butchers", "nl",
        "Dutch slagerijen have their own traditions. Note if they sell Dutch specialties like rookworst, filet americain, or prepare kroketten/bitterballen. Mention if they sell halal meat, as this is relevant for the diverse Dutch population. Note if they do catering or BBQ packages."},

      # Cafes
      {"cafes", "es",
        "Spanish cafe culture: café con leche is the standard, cortado is common. Note if they serve pintxos/tapas with drinks (often free with a drink in Galicia). Mention terraza (terrace) availability. Note if this is more of a traditional Spanish bar or modern coffee shop."},
      {"cafes", "nl",
        "Dutch cafe culture: koffie verkeerd (similar to café latte) and appeltaart (apple pie) are staples. Important: a bruin café is a traditional Dutch pub; a coffeeshop sells cannabis; a koffiehuis serves actual coffee. Make the distinction clear for newcomers. Note terras (terrace) availability."},

      # Car Services
      {"car-services", "es",
        "In Spain, ITV (Inspección Técnica de Vehículos) is the mandatory vehicle inspection. Note if they help with ITV preparation. Mention if they handle foreign-registered vehicles or vehicle import procedures (matriculación). Note specialties (bodywork, electronics, specific brands)."},
      {"car-services", "nl",
        "APK (Algemene Periodieke Keuring) is the mandatory vehicle inspection in the Netherlands. Note if they handle APK. Mention if they help with importing foreign vehicles (RDW kenteken). Dutch road tax (motorrijtuigenbelasting) is separate from purchase tax (BPM). Note specialties."},

      # Cider Houses
      {"cider-houses", "es",
        "Sidrerías are important to Galician social culture, especially in areas like Chantada. Note if they serve locally produced cider (sidra gallega) and if they do traditional escanciado (pouring from height). Note the food menu, as many serve excellent traditional Galician cuisine alongside cider."},
      {"cider-houses", "nl",
        "In the Netherlands this category maps to bruine cafés (traditional brown pubs). These are the social equivalent of sidrerías. They typically serve beer (especially pils and craft/local beers), jenever (Dutch gin), and borrelhapjes (bar snacks like bitterballen and kaas). Note the atmosphere and whether they have a gezellig (cozy) interior."},

      # Dentists
      {"dentists", "es",
        "Dental care in Spain is mostly private. Note if this is a private clinic or if they have any SERGAS (public health) coverage. Mention if they accept seguro privado (private insurance) and which insurers. Note specialties (ortodoncia, implantes, estética dental)."},
      {"dentists", "nl",
        "Dutch dental care is separate from basic health insurance (basisverzekering) - you need additional tandartsverzekering (dental insurance). Note if they accept patients without additional dental insurance and typical costs. Waiting lists can be long, so mention if they accept new patients (nieuwe patiënten)."},

      # Doctors
      {"doctors", "es",
        "SERGAS is Galicia's public health system. The centro de salud is the primary care center. Note if this is a private or public practice, and whether they accept tarjeta sanitaria (public health card). Mention specialties and whether they speak English. Private clinics usually accept major insurance companies."},
      {"doctors", "nl",
        "In the Netherlands, everyone must register with a huisarts (GP) who acts as gatekeeper for all specialist care. This is a huge pain point for newcomers as many practices are full. Note if this huisarts accepts new patients (nieuwe patiënten aannemen). Mention if they have experience with international patients or speak English. GGD handles public health services."},

      # Electricians
      {"electricians", "es",
        "Spanish electrical systems use 230V/50Hz with type F (Schuko) plugs. Older Galician homes often need rewiring. Note if they handle the boletín eléctrico (electrical certificate) needed for connecting utilities. Mention if they do complete renovations or just repairs."},
      {"electricians", "nl",
        "Dutch homes use 230V/50Hz. Note if they handle keuring (inspection) for new installations and can provide NEN 1010 certification. The market for warmtepomp (heat pump) installations and zonnepanelen (solar panels) is growing fast. Mention if they do EV charging point installation (laadpaal)."},

      # Hair Salons
      {"hair-salons", "es",
        "Note typical pricing. In Spain, tipping at hair salons is appreciated but not obligatory. Mention if they specialize in particular styles or treatments. Walk-ins are common in Spain, but note if appointments are recommended."},
      {"hair-salons", "nl",
        "Dutch haircut prices are generally higher than Southern Europe. Note typical pricing. Tipping is not expected but rounding up is common. Walk-ins may be possible but an afspraak (appointment) is usually needed. Note if they have evening or weekend openings."},

      # Language Schools
      {"language-schools", "es",
        "We primarily want schools teaching Spanish and/or Galician to foreigners. Schools teaching only English are less relevant. Note class sizes, schedule flexibility (evening/weekend classes for working adults), and pricing. Mention if they prepare for DELE (Spanish proficiency exam). EOI (Escuela Oficial de Idiomas) offers affordable public language courses."},
      {"language-schools", "nl",
        "In the Netherlands, newcomers often need to pass the inburgeringsexamen (civic integration exam) which includes Dutch language at A2/B1 level. Note if this school prepares for inburgering and NT2 (Nederlands als Tweede Taal) exams. Mention levels offered (A1-C2), class sizes, and whether they cater specifically to English-speaking expats. DUO may fund inburgering courses."},

      # Lawyers
      {"lawyers", "es",
        "Key legal areas for newcomers in Galicia: immigration law (extranjería), NIE/residency procedures, property purchase, inheritance law, and tax law for non-residents. Note specializations and whether they work in English. An abogado de extranjería is specifically an immigration lawyer."},
      {"lawyers", "nl",
        "Key legal areas for expats in the Netherlands: immigration (IND procedures, visa, kennismigrant), housing law (huurcommissie for rental disputes), employment law (ontslag/dismissal, arbeidsovereenkomst), and tax law (30% ruling). Note specializations and whether they work in English. Rechtsbijstand (legal aid) may apply."},

      # Markets
      {"markets", "es",
        "Galician markets (plazas de abastos/mercados municipales) are central to daily life. Note market days and hours. Many sell fresh seafood (mariscos, percebes, pulpo), local cheese (queixo de tetilla, San Simón da Costa), Padrón peppers, and seasonal produce. The Plaza de Abastos in Santiago is world-famous."},
      {"markets", "nl",
        "Weekly markets (weekmarkten) are a Dutch tradition, found in nearly every city and town. Note market days and specialties. Markets often have international food stalls (Turkish, Surinamese, Indonesian, Moroccan). Note if there's a separate Saturday organic/bio market (boerenmarkt). Many markets also sell clothing, flowers, and household goods."},

      # Plumbers
      {"plumbers", "es",
        "Older Galician homes often have outdated plumbing. Note if they handle caldera (boiler) installation and maintenance, as central heating is essential in Galicia's humid climate. Mention if they handle complete bathroom renovations or just repairs."},
      {"plumbers", "nl",
        "Dutch homes often have HR-ketel (high-efficiency boiler) systems and some areas have stadsverwarming (district heating). Note if they handle these systems. Mention if they do complete bathroom renovations. Many older row houses (rijtjeshuizen) have aging pipes. Note availability for spoed (emergency) calls."},

      # Real Estate Agents
      {"real-estate", "es",
        "Note if this agency has experience helping foreigners buy or rent property in Galicia. Mention typical areas they cover and property types. Understanding of NIE requirements and property purchase procedures for non-residents is valuable. Note if they handle rural property (fincas, pazos) as well as urban."},
      {"real-estate", "nl",
        "The Dutch housing market (woningmarkt) is extremely competitive. Note if this makelaar handles both koop (buy) and huur (rent). Overbieden (overbidding above asking price) is common. Mention if they have experience with expat relocations. Note if they help with social housing (sociale huur) applications or know about short-stay housing options."},

      # Restaurants
      {"restaurants", "es",
        "Note whether this restaurant serves traditional Galician cuisine (pulpo á feira, empanada gallega, marisco, caldo gallego, lacón con grelos) vs international food. Highlight local dishes and menú del día (daily set menu, usually excellent value). Mention if they have a terrace. Note typical hours: lunch 13:30-16:00, dinner 21:00-23:00."},
      {"restaurants", "nl",
        "The Netherlands is very multicultural with excellent Indonesian (rijsttafel), Surinamese (roti, pom), Turkish, and Moroccan restaurants alongside Dutch cuisine (stamppot, erwtensoep, kroket). Note the cuisine type and whether they accommodate dietary restrictions (vegetarian/vegan options are very popular in NL). Mention terras (terrace) availability."},

      # Supermarkets
      {"supermarkets", "es",
        "Common chains in Galicia: Gadis (local Galician), Froiz (local), Mercadona, Eroski, Lidl, Carrefour, Dia. Note hours (many close around 21:00-22:00, closed Sundays or limited hours). Mention if they have a fish counter (pescadería) and a deli (charcutería), which are important in Galician food culture."},
      {"supermarkets", "nl",
        "Major chains: Albert Heijn (AH, most common), Jumbo, Lidl, Aldi, Plus, Dirk, Coop. Note which chain and whether it is a large or small format store. AH and Jumbo have bonuskaart loyalty cards. Most close between 20:00-22:00. Mention self-scan (zelfscankassa) availability and whether they have an online ordering/delivery service."},

      # Veterinarians
      {"veterinarians", "es",
        "In Spain, pet identification via microchip is mandatory. Note if they handle the pasaporte europeo para animales (EU pet passport) for international travel, as this is essential for expats moving with pets. Mention emergency (urgencias) availability and whether they offer specialized services."},
      {"veterinarians", "nl",
        "In the Netherlands, dogs must be registered and microchipped. Note if they handle the EU pet passport for international travel. Mention dierenambulance (animal ambulance) service availability and whether they offer spoedgevallen (emergency) care. Note if they handle exotic animals (NAC) in addition to common pets."},

      # Wineries
      {"wineries", "es",
        "Galicia has five Denominaciones de Origen: Rías Baixas (Albariño), Ribeira Sacra (Mencía, Godello), Ribeiro, Valdeorras (Godello), and Monterrei. Note which DO they belong to, whether they offer tours and tastings (visitas y catas), and if they sell directly to the public. Mention their signature grape varieties."},
      {"wineries", "nl",
        "The Netherlands has a very small wine production, mainly in Limburg. This category is more likely to refer to wine shops (wijnwinkels) or slijterijen (liquor stores that often have wine expertise). Note if they offer wine tasting events (wijnproeverij), wine subscriptions, or specialize in particular regions. Note the difference between a slijterij and a wine specialty shop."}
    ]

    for {slug, locale, hints} <- existing_hints do
      execute """
      UPDATE category_translations
      SET enrichment_hints = '#{esc(hints)}',
          updated_at = '#{now}'
      WHERE category_id = (SELECT id FROM categories WHERE slug = '#{slug}')
        AND locale = '#{locale}'
      """
    end
  end

  def down do
    for slug <- ~w(music-schools elementary-schools high-schools libraries municipalities hospitals) do
      execute "DELETE FROM category_translations WHERE category_id = (SELECT id FROM categories WHERE slug = '#{slug}')"
      execute "DELETE FROM categories WHERE slug = '#{slug}'"
    end

    execute "UPDATE category_translations SET enrichment_hints = NULL"
  end

  defp esc(text) do
    String.replace(text, "'", "''")
  end

  defp pg_array(list) do
    items = Enum.map_join(list, ",", &"\"#{esc(&1)}\"")
    "'{#{items}}'"
  end
end
