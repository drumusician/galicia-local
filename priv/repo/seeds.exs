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

alias GaliciaLocal.Directory.{City, Category, Business}

# =============================================================================
# Cities - Favorite cities in Galicia
# =============================================================================

cities = [
  %{
    name: "Ourense",
    slug: "ourense",
    province: "Ourense",
    description: "Known as the 'City of Hot Springs', Ourense offers natural thermal baths, a beautiful historic center, and authentic Galician culture away from the tourist crowds.",
    description_es: "Conocida como la 'Ciudad de las Aguas Termales', Ourense ofrece baños termales naturales, un hermoso centro histórico y auténtica cultura gallega lejos de las multitudes turísticas.",
    latitude: Decimal.new("42.3364"),
    longitude: Decimal.new("-7.8631"),
    population: 105_233,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1583422409516-2895a77efded?w=800"
  },
  %{
    name: "Pontevedra",
    slug: "pontevedra",
    province: "Pontevedra",
    description: "A pedestrian-friendly city famous for being car-free in its historic center. Beautiful plazas, excellent seafood, and a vibrant local culture make it a perfect place to live.",
    description_es: "Una ciudad peatonal famosa por ser libre de coches en su centro histórico. Hermosas plazas, excelente marisco y una vibrante cultura local la convierten en un lugar perfecto para vivir.",
    latitude: Decimal.new("42.4310"),
    longitude: Decimal.new("-8.6447"),
    population: 83_260,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800"
  },
  %{
    name: "Santiago de Compostela",
    slug: "santiago-de-compostela",
    province: "A Coruña",
    description: "The final destination of the Camino de Santiago pilgrimage. A UNESCO World Heritage city with stunning architecture, world-class cuisine, and a youthful university atmosphere.",
    description_es: "El destino final del Camino de Santiago. Una ciudad Patrimonio de la Humanidad con arquitectura impresionante, gastronomía de clase mundial y un ambiente universitario juvenil.",
    latitude: Decimal.new("42.8782"),
    longitude: Decimal.new("-8.5448"),
    population: 97_260,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1539037116277-4db20889f2d4?w=800"
  },
  %{
    name: "Vigo",
    slug: "vigo",
    province: "Pontevedra",
    description: "Galicia's largest city and major port. Modern, dynamic, with beautiful beaches and the stunning Cíes Islands just offshore. Popular among expats for its international atmosphere.",
    description_es: "La ciudad más grande de Galicia y puerto principal. Moderna, dinámica, con hermosas playas y las impresionantes Islas Cíes frente a la costa. Popular entre expatriados por su ambiente internacional.",
    latitude: Decimal.new("42.2328"),
    longitude: Decimal.new("-8.7226"),
    population: 292_817,
    featured: true,
    image_url: "https://images.unsplash.com/photo-1578662996442-48f60103fc96?w=800"
  },
  %{
    name: "A Coruña",
    slug: "a-coruna",
    province: "A Coruña",
    description: "A vibrant coastal city with the iconic Tower of Hercules (the world's oldest working lighthouse), beautiful beaches, and a thriving cultural scene.",
    description_es: "Una vibrante ciudad costera con la icónica Torre de Hércules (el faro en funcionamiento más antiguo del mundo), hermosas playas y una próspera escena cultural.",
    latitude: Decimal.new("43.3623"),
    longitude: Decimal.new("-8.4115"),
    population: 245_711,
    featured: false,
    image_url: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800"
  },
  %{
    name: "Lugo",
    slug: "lugo",
    province: "Lugo",
    description: "Home to the only completely intact Roman walls in the world (UNESCO World Heritage). A historic city with excellent tapas culture and authentic Galician traditions.",
    description_es: "Hogar de las únicas murallas romanas completamente intactas del mundo (Patrimonio de la Humanidad). Una ciudad histórica con excelente cultura de tapas y auténticas tradiciones gallegas.",
    latitude: Decimal.new("43.0097"),
    longitude: Decimal.new("-7.5567"),
    population: 98_025,
    featured: false,
    image_url: "https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=800"
  }
]

IO.puts("Creating cities...")
created_cities =
  for city_data <- cities do
    case City.create(city_data) do
      {:ok, city} ->
        IO.puts("  ✓ Created #{city.name}")
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
  %{name: "Lawyers", name_es: "Abogados", slug: "lawyers", icon: "scale", priority: 1,
    description: "Legal professionals for immigration, real estate, and general matters"},
  %{name: "Accountants", name_es: "Contables", slug: "accountants", icon: "calculator", priority: 1,
    description: "Tax advisors and accounting services"},
  %{name: "Real Estate Agents", name_es: "Inmobiliarias", slug: "real-estate", icon: "home", priority: 1,
    description: "Property agents with experience helping international buyers"},
  %{name: "Doctors", name_es: "Médicos", slug: "doctors", icon: "heart", priority: 1,
    description: "General practitioners and specialists"},
  %{name: "Dentists", name_es: "Dentistas", slug: "dentists", icon: "face-smile", priority: 1,
    description: "Dental care professionals"},
  %{name: "Language Schools", name_es: "Escuelas de Idiomas", slug: "language-schools", icon: "academic-cap", priority: 1,
    description: "Spanish and Galician language courses"},

  # Priority 2: Daily Life
  %{name: "Supermarkets", name_es: "Supermercados", slug: "supermarkets", icon: "shopping-cart", priority: 2,
    description: "Grocery stores and supermarkets"},
  %{name: "Markets", name_es: "Mercados", slug: "markets", icon: "shopping-bag", priority: 2,
    description: "Weekly markets and local produce"},
  %{name: "Bakeries", name_es: "Panaderías", slug: "bakeries", icon: "cake", priority: 2,
    description: "Traditional bread and pastries"},
  %{name: "Butchers", name_es: "Carnicerías", slug: "butchers", icon: "scissors", priority: 2,
    description: "Quality meat and local products"},
  %{name: "Hair Salons", name_es: "Peluquerías", slug: "hair-salons", icon: "scissors", priority: 2,
    description: "Hairdressers and beauty salons"},

  # Priority 3: Lifestyle & Culture
  %{name: "Wineries", name_es: "Bodegas", slug: "wineries", icon: "beaker", priority: 3,
    description: "Wine tasting and vineyard tours"},
  %{name: "Restaurants", name_es: "Restaurantes", slug: "restaurants", icon: "building-storefront", priority: 3,
    description: "Dining from traditional to modern cuisine"},
  %{name: "Cider Houses", name_es: "Sidrerías", slug: "cider-houses", icon: "beaker", priority: 3,
    description: "Traditional cider bars"},
  %{name: "Cafes", name_es: "Cafeterías", slug: "cafes", icon: "sparkles", priority: 3,
    description: "Coffee shops and casual dining"},

  # Priority 4: Practical Services
  %{name: "Plumbers", name_es: "Fontaneros", slug: "plumbers", icon: "wrench", priority: 4,
    description: "Plumbing services and repairs"},
  %{name: "Electricians", name_es: "Electricistas", slug: "electricians", icon: "bolt", priority: 4,
    description: "Electrical services and installations"},
  %{name: "Car Services", name_es: "Talleres", slug: "car-services", icon: "truck", priority: 4,
    description: "Auto repair and maintenance"},
  %{name: "Veterinarians", name_es: "Veterinarios", slug: "veterinarians", icon: "heart", priority: 4,
    description: "Pet care and animal clinics"}
]

IO.puts("\nCreating categories...")
created_categories =
  for cat_data <- categories do
    case Category.create(cat_data) do
      {:ok, category} ->
        IO.puts("  ✓ Created #{category.name}")
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
      description_es: "Cocina gallega tradicional con un toque moderno. Conocido por su excelente pulpo y vinos locales.",
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
      longitude: Decimal.new("-7.8648")
    },
    %{
      name: "Termas de Outariz",
      slug: "termas-outariz",
      address: "Outariz, 32001 Ourense",
      description: "Natural hot springs on the banks of the Miño river. Free public thermal pools with stunning views.",
      description_es: "Aguas termales naturales a orillas del río Miño. Piscinas termales públicas gratuitas con vistas impresionantes.",
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
      longitude: Decimal.new("-7.8833")
    },

    # Santiago restaurants
    %{
      name: "A Horta do Obradoiro",
      slug: "horta-obradoiro",
      address: "Rúa das Hortas, 16, 15705 Santiago de Compostela",
      description: "Elegant restaurant near the Cathedral serving contemporary Galician cuisine with seasonal menus.",
      description_es: "Elegante restaurante cerca de la Catedral sirviendo cocina gallega contemporánea con menús de temporada.",
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
      longitude: Decimal.new("-8.5437")
    },

    # Pontevedra
    %{
      name: "Eirado da Leña",
      slug: "eirado-da-lena",
      address: "Praza da Leña, 3, 36002 Pontevedra",
      description: "Michelin-recommended restaurant in a beautiful plaza. Creative Galician cuisine by Chef Iñaki Bretal.",
      description_es: "Restaurante recomendado por Michelin en una hermosa plaza. Cocina gallega creativa del Chef Iñaki Bretal.",
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
      longitude: Decimal.new("-8.6459")
    },

    # Vigo
    %{
      name: "Abogados García Montero",
      slug: "garcia-montero-abogados",
      address: "Gran Vía, 45, 36204 Vigo",
      description: "Law firm specializing in immigration law, real estate transactions, and residency permits for foreigners.",
      description_es: "Bufete de abogados especializado en derecho de inmigración, transacciones inmobiliarias y permisos de residencia para extranjeros.",
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
      longitude: Decimal.new("-8.7209")
    },
    %{
      name: "Bodegas Terras Gauda",
      slug: "terras-gauda",
      address: "O Rosal, Pontevedra",
      description: "One of Galicia's premier wineries in the Rías Baixas region. Tours and tastings of their famous Albariño wines.",
      description_es: "Una de las principales bodegas de Galicia en la región de Rías Baixas. Visitas y catas de sus famosos vinos Albariño.",
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
      longitude: Decimal.new("-8.8333")
    }
  ]

  IO.puts("\nCreating sample businesses...")
  for biz_data <- sample_businesses do
    case Business.create(biz_data) do
      {:ok, business} ->
        IO.puts("  ✓ Created #{business.name}")
      {:error, error} ->
        IO.puts("  ✗ Error creating #{biz_data.name}: #{inspect(error)}")
    end
  end
end

IO.puts("\n✨ Seeding complete!")
IO.puts("   Cities: #{length(created_cities)}")
IO.puts("   Categories: #{length(created_categories)}")
