module AutoPoster
  # Memilih judul berikutnya untuk satu akun AutoPost:
  #   1. dari Statistik pengunjung instance (drama paling banyak dibuka/ditonton, bukan bot) yang belum pernah
  #      diposting akun ini dan cocok dengan genre otomatis akun (bila diisi);
  #   2. dari pencarian genre otomatis (mis. Sexy / Romance / Dewasa) di beberapa penyedia aktif;
  #   3. bila semua kandidat habis → acak dari beranda ("terbaru") beberapa penyedia aktif.
  # Judul yang sudah/sedang dipakai akun lain di instance yang sama juga dihindari (rotasi antar akun), kecuali
  # kandidat habis. Judul diverifikasi ke API (ada detail + minimal satu episode terbuka) sebelum dipakai.
  class TitlePicker
    STATS_LIMIT    = 300 # kandidat teratas dari statistik yang diperiksa
    HOME_PROVIDERS = 6   # penyedia acak yang dicoba saat fallback
    HOME_TRIES     = 4   # judul acak per penyedia yang diverifikasi
    GENRE_TRIES    = 4   # judul per hasil pencarian genre yang diverifikasi

    # Kata kunci pencarian + pencocokan genre per label (lowercase). Label lain dipakai apa adanya.
    GENRE_KEYWORDS = {
      "sexy"    => %w[sexy seksi hot],
      "romance" => %w[romance romantis romantic cinta love],
      "dewasa"  => %w[dewasa adult mature 18+]
    }.freeze

    def initialize(auto_post, locale: "id")
      @ap = auto_post
      @locale = locale.to_s
    end

    # Mengganti judul akun (progres di-reset, judul lama dicatat). Raise RunError bila tidak ada kandidat.
    def pick!
      choice = from_stats || from_genres || from_latest
      raise AutoPost::RunError, I18n.t("admin.auto_post.no_title_found") unless choice
      @ap.start_title!(**choice)
      choice
    end

    private
    # Judul yang sudah diposting akun ini + yang sudah/sedang dipakai akun lain di instance ini.
    def posted
      @posted ||= begin
        set = Set.new(Array(@ap.posted_titles).map(&:to_s))
        set << @ap.title_key if @ap.drama_id.present?
        if @ap.respond_to?(:sibling_title_keys)
          set.merge(@ap.sibling_title_keys)
        else
          AutoPost.where(instance_id: @ap.instance_id).where.not(id: @ap.id).pluck(:posted_titles, :provider_slug, :drama_id).each do |titles, slug, id|
            Array(titles).each { |t| set << t.to_s }
            set << "#{slug}:#{id}" if id.present?
          end
        end
        set
      end
    end

    def providers = @providers ||= Provider.enabled.supported.index_by(&:slug)
    def genres = @genres ||= @ap.genre_list
    def keywords_for(genre) = GENRE_KEYWORDS[genre.to_s.downcase] || [ genre.to_s.downcase ]

    # Statistik: hanya judul yang genre-nya cocok (judul tanpa info genre dilewati bila genre otomatis diisi).
    def from_stats
      counts = Visit.humans.where(instance_id: @ap.instance_id, kind: %w[drama watch]).where.not(drama_id: nil)
                    .group(:provider, :drama_id).count
      counts.sort_by { |_, c| -c }.first(STATS_LIMIT).each do |(slug, id), _|
        next if posted.include?("#{slug}:#{id}") || providers[slug].nil?
        choice = verify(providers[slug], id, genre: :strict) and return choice.merge(source: "stats")
      end
      nil
    end

    # Pencarian genre di penyedia: satu kata kunci acak per genre per penyedia agar hemat request API.
    # Hasil pencarian tanpa info genre tetap diterima (sudah tersaring oleh kata kunci).
    def from_genres
      return nil if genres.empty?
      providers.values.shuffle.first(HOME_PROVIDERS).each do |provider|
        catalog = DracinApi::Catalog.for(provider, lang: @locale)
        genres.shuffle.each do |g|
          items = catalog.search(keywords_for(g).sample, page: 1).items
                         .reject { |d| posted.include?("#{provider.slug}:#{d.id}") }.shuffle
          items.first(GENRE_TRIES).each do |d|
            choice = verify(provider, d.id, genre: :soft) and return choice.merge(source: "genre:#{g}")
          end
        rescue DracinApi::Error => e
          Rails.logger.warn("[TitlePicker] #{provider.slug} genre #{g}: #{e.message}")
        end
      end
      nil
    end

    def from_latest
      providers.values.shuffle.first(HOME_PROVIDERS).each do |provider|
        items = DracinApi::Catalog.for(provider, lang: @locale).home.flat_map(&:items)
                                  .reject { |d| posted.include?("#{provider.slug}:#{d.id}") }.shuffle
        items.first(HOME_TRIES).each do |d|
          choice = verify(provider, d.id, genre: :soft) and return choice.merge(source: "latest")
        end
      rescue DracinApi::Error => e
        Rails.logger.warn("[TitlePicker] #{provider.slug} home: #{e.message}")
      end
      nil
    end

    # genre: :strict = genre drama harus cocok; :soft = cocok atau tidak ada info genre; nil = tanpa cek.
    def verify(provider, id, genre: nil)
      catalog = DracinApi::Catalog.for(provider, lang: @locale)
      drama = catalog.detail(id)
      return nil if drama.nil? || drama.title.blank? || !genre_match?(drama, genre)
      return nil if catalog.episodes(id).none? { |e| !e.locked }
      { provider_slug: provider.slug, drama_id: id.to_s, drama_title: drama.title.to_s }
    rescue DracinApi::Error => e
      Rails.logger.warn("[TitlePicker] #{provider.slug}/#{id}: #{e.message}")
      nil
    end

    def genre_match?(drama, mode)
      return true if mode.nil? || genres.empty?
      found = Array(drama.genres).map { |x| x.to_s.downcase }
      return mode == :soft if found.empty?
      genres.any? { |g| kws = keywords_for(g); found.any? { |x| kws.any? { |k| x.include?(k) } } }
    end
  end
end
