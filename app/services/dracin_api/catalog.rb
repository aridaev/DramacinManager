module DracinApi
  # Lapisan di atas adapter per-provider: normalisasi ringan + cache. Semua data berasal dari API;
  # jika API gagal, error DracinApi::Error dilempar ke controller (tidak ada data contoh).
  class Catalog
    Drama   = Struct.new(:provider, :id, :title, :cover, :synopsis, :genres, :language, :episodes, :rating, :year, :status, keyword_init: true)
    Episode = Struct.new(:number, :title, :thumbnail, :duration, :locked, :payload, keyword_init: true)
    # sources: [ { label: "720p", url: } ] — semua varian kualitas yang bisa dipilih pemutar. url = varian default.
    Stream  = Struct.new(:url, :format, :quality, :sources, :subtitles, :episode, :cookies, keyword_init: true)
    Section = Struct.new(:title, :items, keyword_init: true)
    Page    = Struct.new(:items, :page, :has_more, keyword_init: true)

    CACHE_TTL = 30.minutes
    PLAY_TTL  = 5.minutes # URL video sering ber-signature dan kedaluwarsa
    RACE_TTL  = 20.seconds # saat cache kedaluwarsa, request lain tetap dapat nilai lama selama satu request memperbarui

    attr_reader :provider

    def self.for(provider, lang: I18n.locale)
      new(provider, DracinApi::Adapters.for(provider, lang: lang.to_s), lang: lang.to_s)
    end

    def initialize(provider, adapter, lang: "en")
      @provider = provider
      @adapter = adapter
      @lang = lang
    end

    def slug = provider.slug
    def supported? = @adapter.present?

    def home
      fetch("home") do
        adapter.home.each { |s| s.items = clean(s.items) }.reject { |s| s.items.empty? }
      end
    end

    def search(keyword, page: 1)
      fetch("search", keyword, page) { adapter.search(keyword, page: page).tap { |pg| pg.items = clean(pg.items) } }
    end

    def genre(type, page: 1)
      # Tiap provider punya skema kategori sendiri; untuk sekarang genre dipetakan ke pencarian kata kunci.
      search(type.to_s.tr("-", " "), page: page)
    end

    def detail(id)
      fetch("detail", id) { clean_genres(adapter.detail(id)) }
    end

    def episodes(id)
      fetch("episodes", id) { Array(adapter.episodes(id)).sort_by(&:number) }
    end

    def play(id, episode)
      fetch("play", id, episode, ttl: PLAY_TTL) do
        adapter.prime_episodes(id, episodes(id))
        adapter.play(id, episode)
      end
    end

    private
    def adapter
      @adapter or raise Unsupported, I18n.t("dracin_api.errors.unsupported", provider: provider.name)
    end

    def clean(items)
      Array(items).reject { |d| d.id.blank? || d.title.blank? }.uniq(&:id).each { |d| clean_genres(d) }
    end

    def clean_genres(drama)
      drama.genres = Array(drama.genres).map { |g| g.to_s.strip }.reject { |g| g.blank? || g.parameterize.blank? }.uniq.first(5)
      drama
    end

    STALE_TTL = 6.hours # salinan "basi" dipakai bila upstream gagal/timeout (host *.goodbos.online sering lambat)

    def fetch(*key, ttl: CACHE_TTL)
      ckey = [ "dracin_api", "v2", slug, @lang, *key ]
      Rails.cache.fetch(ckey, expires_in: ttl, race_condition_ttl: RACE_TTL) do
        value = yield
        Rails.cache.write([ *ckey, "stale" ], value, expires_in: STALE_TTL) unless value.nil?
        value
      end
    rescue DracinApi::Error => e
      stale = Rails.cache.read([ *ckey, "stale" ])
      raise if stale.nil?
      Rails.logger.warn("[DracinApi] #{slug} #{key.first}: #{e.message} → pakai cache lama")
      stale
    end
  end
end
