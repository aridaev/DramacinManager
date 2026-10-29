module AutoPoster
  # Memilih judul berikutnya untuk satu akun AutoPost:
  #   1. dari Statistik pengunjung instance (drama paling banyak dibuka/ditonton, bukan bot) yang belum pernah
  #      diposting akun ini;
  #   2. bila semua judul statistik sudah terpakai → acak dari beranda ("terbaru") beberapa penyedia aktif.
  # Judul diverifikasi ke API (ada detail + minimal satu episode terbuka) sebelum dipakai.
  class TitlePicker
    STATS_LIMIT    = 300 # kandidat teratas dari statistik yang diperiksa
    HOME_PROVIDERS = 6   # penyedia acak yang dicoba saat fallback
    HOME_TRIES     = 4   # judul acak per penyedia yang diverifikasi

    def initialize(auto_post, locale: "id")
      @ap = auto_post
      @locale = locale.to_s
    end

    # Mengganti judul akun (progres di-reset, judul lama dicatat). Raise RunError bila tidak ada kandidat.
    def pick!
      choice = from_stats || from_latest
      raise AutoPost::RunError, I18n.t("admin.auto_post.no_title_found") unless choice
      @ap.start_title!(**choice)
      choice
    end

    private
    def posted
      @posted ||= Set.new(Array(@ap.posted_titles).map(&:to_s)).tap { |s| s << @ap.title_key if @ap.drama_id.present? }
    end

    def providers = @providers ||= Provider.enabled.supported.index_by(&:slug)

    def from_stats
      counts = Visit.humans.where(instance_id: @ap.instance_id, kind: %w[drama watch]).where.not(drama_id: nil)
                    .group(:provider, :drama_id).count
      counts.sort_by { |_, c| -c }.first(STATS_LIMIT).each do |(slug, id), _|
        next if posted.include?("#{slug}:#{id}") || providers[slug].nil?
        choice = verify(providers[slug], id) and return choice.merge(source: "stats")
      end
      nil
    end

    def from_latest
      providers.values.shuffle.first(HOME_PROVIDERS).each do |provider|
        items = DracinApi::Catalog.for(provider, lang: @locale).home.flat_map(&:items)
                                  .reject { |d| posted.include?("#{provider.slug}:#{d.id}") }.shuffle
        items.first(HOME_TRIES).each do |d|
          choice = verify(provider, d.id) and return choice.merge(source: "latest")
        end
      rescue DracinApi::Error => e
        Rails.logger.warn("[TitlePicker] #{provider.slug} home: #{e.message}")
      end
      nil
    end

    def verify(provider, id)
      catalog = DracinApi::Catalog.for(provider, lang: @locale)
      drama = catalog.detail(id)
      return nil if drama.nil? || drama.title.blank? || catalog.episodes(id).none? { |e| !e.locked }
      { provider_slug: provider.slug, drama_id: id.to_s, drama_title: drama.title.to_s }
    rescue DracinApi::Error => e
      Rails.logger.warn("[TitlePicker] #{provider.slug}/#{id}: #{e.message}")
      nil
    end
  end
end
