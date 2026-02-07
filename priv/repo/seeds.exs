# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     GaliciaLocal.Repo.insert!(%GaliciaLocal.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias GaliciaLocal.Directory.{City, Category, Business, CityTranslation, CategoryTranslation, BusinessTranslation}

# =============================================================================
# Cities - Favorite cities in Galicia
# =============================================================================

cities = [
  %{
    name: "Ourense",
    slug: "ourense",
    province: "Ourense",
    description: "Known as the 'City of Hot Springs', Ourense offers natural thermal baths, a beautiful historic center, and authentic Galician culture away from the tourist crowds.",
    latitude: Decimal.new("42.3364"),
    longitude: Decimal.new("-7.8631"),
    population: 105_233,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1583422409516-2895a77efded?w=800",
    _es: "Conocida como la 'Ciudad de las Aguas Termales', Ourense ofrece baños termales naturales, un hermoso centro histórico y auténtica cultura gallega lejos de las multitudes turísticas."
  },
  %{
    name: "Pontevedra",
    slug: "pontevedra",
    province: "Pontevedra",
    description: "A pedestrian-friendly city famous for being car-free in its historic center. Beautiful plazas, excellent seafood, and a vibrant local culture make it a perfect place to live.",
    latitude: Decimal.new("42.4310"),
    longitude: Decimal.new("-8.6447"),
    population: 83_260,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800",
    _es: "Una ciudad peatonal famosa por ser libre de coches en su centro histórico. Hermosas plazas, excelente marisco y una vibrante cultura local la convierten en un lugar perfecto para vivir."
  },
  %{
    name: "Santiago de Compostela",
    slug: "santiago-de-compostela",
    province: "A Coruña",
    description: "The final destination of the Camino de Santiago pilgrimage. A UNESCO World Heritage city with stunning architecture, world-class cuisine, and a youthful university atmosphere.",
    latitude: Decimal.new("42.8782"),
    longitude: Decimal.new("-8.5448"),
    population: 97_260,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1539037116277-4db20889f2d4?w=800",
    _es: "El destino final del Camino de Santiago. Una ciudad Patrimonio de la Humanidad con arquitectura impresionante, gastronomía de clase mundial y un ambiente universitario juvenil."
  },
  %{
    name: "Vigo",
    slug: "vigo",
    province: "Pontevedra",
    description: "Galicia's largest city and major port. Modern, dynamic, with beautiful beaches and the stunning Cíes Islands just offshore. Popular among expats for its international atmosphere.",
    latitude: Decimal.new("42.2328"),
    longitude: Decimal.new("-8.7226"),
    population: 292_817,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1578662996442-48f60103fc96?w=800",
    _es: "La ciudad más grande de Galicia y puerto principal. Moderna, dinámica, con hermosas playas y las impresionantes Islas Cíes frente a la costa. Popular entre expatriados por su ambiente internacional."
  },
  %{
    name: "A Coruña",
    slug: "a-coruna",
    province: "A Coruña",
    description: "A vibrant coastal city with the iconic Tower of Hercules (the world's oldest working lighthouse), beautiful beaches, and a thriving cultural scene.",
    latitude: Decimal.new("43.3623"),
    longitude: Decimal.new("-8.4115"),
    population: 245_711,
    featured: false,
    image_url: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800",
    _es: "Una vibrante ciudad costera con la icónica Torre de Hércules (el faro en funcionamiento más antiguo del mundo), hermosas playas y una próspera escena cultural."
  },
  %{
    name: "Lugo",
    slug: "lugo",
    province: "Lugo",
    description: "Home to the only completely intact Roman walls in the world (UNESCO World Heritage). A historic city with excellent tapas culture and authentic Galician traditions.",
    latitude: Decimal.new("43.0097"),
    longitude: Decimal.new("-7.5567"),
    population: 98_025,
    featured: false,
    image_url: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800",
    _es: "Hogar de las únicas murallas romanas completamente intactas del mundo (Patrimonio de la Humanidad). Una ciudad histórica con excelente cultura de tapas y auténticas tradiciones gallegas."
  }
]

IO.puts("Creating cities...")
created_cities =
  for city_data <- cities do
    {es_desc, city_attrs} = Map.pop(city_data, :_es)
    case City.create(city_attrs) do
      {:ok, city} ->
        IO.puts("  ✓ Created #{city.name}")
        if es_desc do
          CityTranslation.upsert(%{city_id: city.id, locale: "es", description: es_desc})
        end
        city
      {:error, error} ->
        IO.puts("  ✗ Error creating #{city_data.name}: #{inspect(error)}")
        nil
    end
  end
  |> Enum.reject(&is_nil/1)

# =============================================================================
# Categories - Organized by priority for expats
# =============================================================================

categories = [
  # Priority 1: Expat Essentials
  %{name: "Lawyers", slug: "lawyers", icon: "scale", priority: 1,
    description: "Legal professionals for immigration, real estate, and general matters", _es: "Abogados"},
  %{name: "Accountants", slug: "accountants", icon: "calculator", priority: 1,
    description: "Tax advisors and accounting services", _es: "Contables"},
  %{name: "Real Estate Agents", slug: "real-estate", icon: "home", priority: 1,
    description: "Property agents with experience helping international buyers", _es: "Inmobiliarias"},
  %{name: "Doctors", slug: "doctors", icon: "heart", priority: 1,
    description: "General practitioners and specialists", _es: "Médicos"},
  %{name: "Dentists", slug: "dentists", icon: "face-smile", priority: 1,
    description: "Dental care professionals", _es: "Dentistas"},
  %{name: "Language Schools", slug: "language-schools", icon: "academic-cap", priority: 1,
    description: "Spanish and Galician language courses", _es: "Escuelas de Idiomas"},

  # Priority 2: Daily Life
  %{name: "Supermarkets", slug: "supermarkets", icon: "shopping-cart", priority: 2,
    description: "Grocery stores and supermarkets", _es: "Supermercados"},
  %{name: "Markets", slug: "markets", icon: "shopping-bag", priority: 2,
    description: "Weekly markets and local produce", _es: "Mercados"},
  %{name: "Bakeries", slug: "bakeries", icon: "cake", priority: 2,
    description: "Traditional bread and pastries", _es: "Panaderías"},
  %{name: "Butchers", slug: "butchers", icon: "scissors", priority: 2,
    description: "Quality meat and local products", _es: "Carnicerías"},
  %{name: "Hair Salons", slug: "hair-salons", icon: "scissors", priority: 2,
    description: "Hairdressers and beauty salons", _es: "Peluquerías"},

  # Priority 3: Lifestyle & Culture
  %{name: "Wineries", slug: "wineries", icon: "beaker", priority: 3,
    description: "Wine tasting and vineyard tours", _es: "Bodegas"},
  %{name: "Restaurants", slug: "restaurants", icon: "building-storefront", priority: 3,
    description: "Dining from traditional to modern cuisine", _es: "Restaurantes"},
  %{name: "Cider Houses", slug: "cider-houses", icon: "beaker", priority: 3,
    description: "Traditional cider bars", _es: "Sidrerías"},
  %{name: "Cafes", slug: "cafes", icon: "sparkles", priority: 3,
    description: "Coffee shops and casual dining", _es: "Cafeterías"},

  # Priority 4: Practical Services
  %{name: "Plumbers", slug: "plumbers", icon: "wrench", priority: 4,
    description: "Plumbing services and repairs", _es: "Fontaneros"},
  %{name: "Electricians", slug: "electricians", icon: "bolt", priority: 4,
    description: "Electrical services and installations", _es: "Electricistas"},
  %{name: "Car Services", slug: "car-services", icon: "truck", priority: 4,
    description: "Auto repair and maintenance", _es: "Talleres"},
  %{name: "Veterinarians", slug: "veterinarians", icon: "heart", priority: 4,
    description: "Pet care and animal clinics", _es: "Veterinarios"}
]

IO.puts("\nCreating categories...")
created_categories =
  for cat_data <- categories do
    {es_name, cat_attrs} = Map.pop(cat_data, :_es)
    case Category.create(cat_attrs) do
      {:ok, category} ->
        IO.puts("  ✓ Created #{category.name}")
        if es_name do
          CategoryTranslation.upsert(%{category_id: category.id, locale: "es", name: es_name})
        end
        category
      {:error, error} ->
        IO.puts("  ✗ Error creating #{cat_data.name}: #{inspect(error)}")
        nil
    end
  end
  |> Enum.reject(&is_nil/1)

# =============================================================================
# Sample Businesses - A few real examples to get started
# =============================================================================

# Find the cities and categories we need
ourense = Enum.find(created_cities, &(&1.slug == "ourense"))
pontevedra = Enum.find(created_cities, &(&1.slug == "pontevedra"))
santiago = Enum.find(created_cities, &(&1.slug == "santiago-de-compostela"))
vigo = Enum.find(created_cities, &(&1.slug == "vigo"))

restaurants = Enum.find(created_categories, &(&1.slug == "restaurants"))
lawyers = Enum.find(created_categories, &(&1.slug == "lawyers"))
wineries = Enum.find(created_categories, &(&1.slug == "wineries"))
cafes = Enum.find(created_categories, &(&1.slug == "cafes"))

if ourense && pontevedra && santiago && vigo && restaurants && lawyers && wineries && cafes do
  sample_businesses = [
    # Ourense restaurants
    %{
      name: "O Catro",
      slug: "o-catro",
      address: "Rúa Progreso, 78, 32003 Ourense",
      description: "Traditional Galician cuisine with a modern twist. Known for excellent octopus and local wines.",
      summary: "Top-rated traditional restaurant with modern flair",
      rating: Decimal.new("4.6"),
      review_count: 234,
      price_level: 2,
      speaks_english: true,
      speaks_english_confidence: Decimal.new("0.7"),
      languages_spoken: [:es, :en, :gl],
      highlights: ["Excellent octopus", "Great wine selection", "Friendly staff"],
      warnings: ["Reservations recommended on weekends"],
      status: :enriched,
      source: :manual,
      city_id: ourense.id,
      category_id: restaurants.id,
      latitude: Decimal.new("42.3391"),
      longitude: Decimal.new("-7.8648"),
      _es: "Cocina gallega tradicional con un toque moderno. Conocido por su excelente pulpo y vinos locales."
    },
    %{
      name: "Termas de Outariz",
      slug: "termas-outariz",
      address: "Outariz, 32001 Ourense",
      description: "Natural hot springs on the banks of the Miño river. Free public thermal pools with stunning views.",
      summary: "Free natural hot springs by the river",
      rating: Decimal.new("4.8"),
      review_count: 1523,
      speaks_english: false,
      speaks_english_confidence: Decimal.new("0.3"),
      languages_spoken: [:es, :gl],
      highlights: ["Free entry", "Natural setting", "Hot mineral water"],
      warnings: ["Bring your own towel", "Can be crowded on weekends"],
      status: :enriched,
      source: :manual,
      city_id: ourense.id,
      category_id: cafes.id,
      latitude: Decimal.new("42.3167"),
      longitude: Decimal.new("-7.8833"),
      _es: "Aguas termales naturales a orillas del río Miño. Piscinas termales públicas gratuitas con vistas impresionantes."
    },

    # Santiago restaurants
    %{
      name: "A Horta do Obradoiro",
      slug: "horta-obradoiro",
      address: "Rúa das Hortas, 16, 15705 Santiago de Compostela",
      description: "Elegant restaurant near the Cathedral serving contemporary Galician cuisine with seasonal menus.",
      summary: "Fine dining with Cathedral views",
      rating: Decimal.new("4.7"),
      review_count: 567,
      price_level: 3,
      speaks_english: true,
      speaks_english_confidence: Decimal.new("0.9"),
      languages_spoken: [:es, :en, :gl, :fr],
      highlights: ["Tasting menus", "Wine pairing", "Romantic atmosphere"],
      warnings: ["Advance booking required"],
      status: :enriched,
      source: :manual,
      city_id: santiago.id,
      category_id: restaurants.id,
      latitude: Decimal.new("42.8789"),
      longitude: Decimal.new("-8.5437"),
      _es: "Elegante restaurante cerca de la Catedral sirviendo cocina gallega contemporánea con menús de temporada."
    },

    # Pontevedra
    %{
      name: "Eirado da Leña",
      slug: "eirado-da-lena",
      address: "Praza da Leña, 3, 36002 Pontevedra",
      description: "Michelin-recommended restaurant in a beautiful plaza. Creative Galician cuisine by Chef Iñaki Bretal.",
      summary: "Michelin-recommended creative cuisine",
      rating: Decimal.new("4.8"),
      review_count: 789,
      price_level: 3,
      speaks_english: true,
      speaks_english_confidence: Decimal.new("0.85"),
      languages_spoken: [:es, :en, :gl],
      highlights: ["Creative dishes", "Beautiful location", "Excellent service"],
      warnings: ["Book well in advance"],
      status: :enriched,
      source: :manual,
      city_id: pontevedra.id,
      category_id: restaurants.id,
      latitude: Decimal.new("42.4309"),
      longitude: Decimal.new("-8.6459"),
      _es: "Restaurante recomendado por Michelin en una hermosa plaza. Cocina gallega creativa del Chef Iñaki Bretal."
    },

    # Vigo
    %{
      name: "Abogados García Montero",
      slug: "garcia-montero-abogados",
      address: "Gran Vía, 45, 36204 Vigo",
      description: "Law firm specializing in immigration law, real estate transactions, and residency permits for foreigners.",
      summary: "Immigration and real estate lawyers for expats",
      rating: Decimal.new("4.5"),
      review_count: 89,
      price_level: 2,
      speaks_english: true,
      speaks_english_confidence: Decimal.new("0.95"),
      languages_spoken: [:es, :en, :pt],
      highlights: ["English speaking", "NIE/Residency specialists", "Real estate expertise"],
      warnings: ["Appointment required"],
      status: :enriched,
      source: :manual,
      city_id: vigo.id,
      category_id: lawyers.id,
      latitude: Decimal.new("42.2367"),
      longitude: Decimal.new("-8.7209"),
      _es: "Bufete de abogados especializado en derecho de inmigración, transacciones inmobiliarias y permisos de residencia para extranjeros."
    },
    %{
      name: "Bodegas Terras Gauda",
      slug: "terras-gauda",
      address: "O Rosal, Pontevedra",
      description: "One of Galicia's premier wineries in the Rías Baixas region. Tours and tastings of their famous Albariño wines.",
      summary: "Premier Albariño winery with tours",
      rating: Decimal.new("4.9"),
      review_count: 456,
      price_level: 3,
      speaks_english: true,
      speaks_english_confidence: Decimal.new("0.9"),
      languages_spoken: [:es, :en, :gl, :de],
      highlights: ["Beautiful vineyards", "Excellent tours", "Award-winning wines"],
      warnings: ["Book tours in advance", "Not accessible by public transport"],
      status: :enriched,
      source: :manual,
      city_id: vigo.id,
      category_id: wineries.id,
      latitude: Decimal.new("42.0833"),
      longitude: Decimal.new("-8.8333"),
      _es: "Una de las principales bodegas de Galicia en la región de Rías Baixas. Visitas y catas de sus famosos vinos Albariño."
    }
  ]

  IO.puts("\nCreating sample businesses...")
  for biz_data <- sample_businesses do
    {es_desc, biz_attrs} = Map.pop(biz_data, :_es)
    case Business.create(biz_attrs) do
      {:ok, business} ->
        IO.puts("  ✓ Created #{business.name}")
        if es_desc do
          BusinessTranslation.upsert(%{business_id: business.id, locale: "es", description: es_desc})
        end
      {:error, error} ->
        IO.puts("  ✗ Error creating #{biz_data.name}: #{inspect(error)}")
    end
  end
end

IO.puts("\n✨ Seeding complete!")
IO.puts("   Cities: #{length(created_cities)}")
IO.puts("   Categories: #{length(created_categories)}")
