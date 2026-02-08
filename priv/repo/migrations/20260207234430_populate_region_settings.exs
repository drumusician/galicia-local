defmodule GaliciaLocal.Repo.Migrations.PopulateRegionSettings do
  use Ecto.Migration

  def up do
    galicia_settings = galicia_settings()
    netherlands_settings = netherlands_settings()

    repo().query!(
      "UPDATE regions SET tagline = $1, hero_image_url = $2, settings = $3 WHERE slug = $4",
      [
        "Celtic heritage, incredible seafood, warm communities",
        "https://images.unsplash.com/photo-1684931772184-75c6fb13c1f9?w=1920&q=80",
        galicia_settings,
        "galicia"
      ]
    )

    repo().query!(
      "UPDATE regions SET tagline = $1, hero_image_url = $2, settings = $3 WHERE slug = $4",
      [
        "Cycling culture, canals, welcoming expat scene",
        "https://images.unsplash.com/photo-1534351590666-13e3e96b5017?w=1920&q=80",
        netherlands_settings,
        "netherlands"
      ]
    )
  end

  def down do
    execute """
    UPDATE regions SET tagline = NULL, hero_image_url = NULL, settings = '{}'::jsonb
    WHERE slug IN ('galicia', 'netherlands')
    """
  end

  defp galicia_settings do
    %{
      "phrases" => [
        %{"local" => "Bos días", "english" => "Good morning", "spanish" => "Buenos días", "usage" => "Morning greeting until ~2pm"},
        %{"local" => "Boas tardes", "english" => "Good afternoon", "spanish" => "Buenas tardes", "usage" => "Afternoon greeting 2pm-8pm"},
        %{"local" => "Boas noites", "english" => "Good evening", "spanish" => "Buenas noches", "usage" => "Evening greeting after 8pm"},
        %{"local" => "Moitas grazas", "english" => "Thank you very much", "spanish" => "Muchas gracias", "usage" => "Showing appreciation"},
        %{"local" => "Por favor", "english" => "Please", "spanish" => "Por favor", "usage" => "Being polite"},
        %{"local" => "Ata logo", "english" => "See you later", "spanish" => "Hasta luego", "usage" => "Casual goodbye"},
        %{"local" => "Bo proveito", "english" => "Enjoy your meal", "spanish" => "Buen provecho", "usage" => "Said before eating"},
        %{"local" => "Saúde!", "english" => "Cheers!", "spanish" => "¡Salud!", "usage" => "Toast when drinking"}
      ],
      "cultural_tips" => [
        %{"icon" => "clock", "title" => "The Siesta is Real", "tip" => "Many shops close 2-5pm. Plan errands for mornings or evenings."},
        %{"icon" => "sun", "title" => "Lunch is the Main Meal", "tip" => "Galicians eat lunch 2-4pm. Restaurants are empty at noon."},
        %{"icon" => "sparkles", "title" => "Free Tapas Culture", "tip" => "In many bars, tapas come free with drinks. Just order a caña!"},
        %{"icon" => "banknotes", "title" => "Cash is King", "tip" => "Smaller shops often prefer cash. Always have some euros handy."},
        %{"icon" => "hand-raised", "title" => "Greet Everyone", "tip" => "Say 'Bos días' when entering shops. It's expected and appreciated."},
        %{"icon" => "fire", "title" => "Thermal Springs", "tip" => "Ourense has free public hot springs. Bring a towel and join the locals!"}
      ],
      "enrichment_context" => %{
        "name" => "Galicia",
        "country" => "Spain",
        "main_language" => "Spanish",
        "local_language" => "Galician (Galego)",
        "language_code" => "es",
        "local_greeting" => "Bos días",
        "typical_business" => "traditional family-run tapas bar",
        "food_examples" => "pulpo, tapas, marisquería",
        "cultural_examples" => [
          "Pulperías are central to Galician social life",
          "The siesta is real - many shops close 2-5pm",
          "Tapas are often free with drinks",
          "Galicians value personal relationships - expect friendly chat"
        ]
      }
    }
  end

  defp netherlands_settings do
    %{
      "phrases" => [
        %{"local" => "Goedemorgen", "english" => "Good morning", "usage" => "Morning greeting"},
        %{"local" => "Goedemiddag", "english" => "Good afternoon", "usage" => "Afternoon greeting"},
        %{"local" => "Goedenavond", "english" => "Good evening", "usage" => "Evening greeting"},
        %{"local" => "Dank je wel", "english" => "Thank you", "usage" => "Informal thanks"},
        %{"local" => "Alsjeblieft", "english" => "Please / Here you go", "usage" => "Being polite or handing something"},
        %{"local" => "Tot ziens", "english" => "Goodbye", "usage" => "Formal goodbye"},
        %{"local" => "Doei", "english" => "Bye", "usage" => "Casual goodbye"},
        %{"local" => "Proost!", "english" => "Cheers!", "usage" => "Toast when drinking"},
        %{"local" => "Gezellig", "english" => "Cozy/fun/nice atmosphere", "usage" => "The most Dutch word - describes a good vibe"},
        %{"local" => "Lekker", "english" => "Tasty/nice/good", "usage" => "Used for food, weather, feelings"}
      ],
      "cultural_tips" => [
        %{"icon" => "chat-bubble-left-right", "title" => "Be Direct", "tip" => "Dutch people value directness. It's not rude, it's efficient!"},
        %{"icon" => "truck", "title" => "Cycle Everywhere", "tip" => "Get a bike! It's the main transport. Learn the rules and always signal."},
        %{"icon" => "banknotes", "title" => "Split the Bill", "tip" => "'Going Dutch' is real. Each person pays for themselves at dinner."},
        %{"icon" => "cake", "title" => "Birthday Circles", "tip" => "At birthdays, you sit in a circle and congratulate everyone, not just the birthday person."},
        %{"icon" => "calendar", "title" => "Agenda Culture", "tip" => "Dutch people plan everything weeks ahead. Spontaneous visits are rare."},
        %{"icon" => "sparkles", "title" => "Hagelslag for Breakfast", "tip" => "Chocolate sprinkles on bread for breakfast is totally normal here!"}
      ],
      "enrichment_context" => %{
        "name" => "Netherlands",
        "country" => "Netherlands",
        "main_language" => "Dutch",
        "local_language" => nil,
        "language_code" => "nl",
        "local_greeting" => "Hoi or Goedemorgen",
        "typical_business" => "local family bakery or brown café (bruin café)",
        "food_examples" => "stroopwafels, bitterballen, Indonesian food",
        "cultural_examples" => [
          "Dutch directness is normal - it's not rude, just honest",
          "Most shops close early (17:00-18:00) and on Sundays",
          "Appointments are everything - always book ahead",
          "Splitting the bill (going Dutch) is completely normal"
        ]
      }
    }
  end
end
