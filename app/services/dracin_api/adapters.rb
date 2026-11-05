module DracinApi
  # Registry adapter per provider. Setiap provider DracinAPI punya host dan skema API sendiri
  # (lihat field `api` di /api/status), jadi tiap provider butuh adapter.
  module Adapters
    REGISTRY = {
      "cubetv"     => "DracinApi::Adapters::Cubetv",
      "dramabite"    => "DracinApi::Adapters::Dramabite",
      "dotdrama"   => "DracinApi::Adapters::Dotdrama",
      "rapidtv"    => "DracinApi::Adapters::Rapidtv",
      "happyshort" => "DracinApi::Adapters::Happyshort",
      "bonustv"    => "DracinApi::Adapters::Bonustv",
      # "raptdrama" => "DracinApi::Adapters::Raptdrama", # upstream detail/episodes kosong (Okt 2026); aktifkan bila sudah pulih
      "dramabox"   => "DracinApi::Adapters::Dramabox",
      "dramawave"  => "DracinApi::Adapters::Dramawave",
      "flextv"     => "DracinApi::Adapters::Flextv",
      "goodshort"  => "DracinApi::Adapters::Goodshort",
      "flickreels" => "DracinApi::Adapters::Flickreels",
      "pinedrama"  => "DracinApi::Adapters::Pinedrama",
      "freereels"  => "DracinApi::Adapters::Freereels",
      "melolo"     => "DracinApi::Adapters::Melolo",
      "microdrama" => "DracinApi::Adapters::Microdrama",
      "moboreels"  => "DracinApi::Adapters::Moboreels",
      "netshort"   => "DracinApi::Adapters::Netshort",
      "reelbuzz"   => "DracinApi::Adapters::Reelbuzz",
      "reelshort"    => "DracinApi::Adapters::Reelshort",
      "reelife"    => "DracinApi::Adapters::Reelife",
      "serialplus" => "DracinApi::Adapters::Serialplus",
      "shortmax"   => "DracinApi::Adapters::Shortmax",
      "shortswave" => "DracinApi::Adapters::Shortswave",
      "stardusttv" => "DracinApi::Adapters::Stardusttv",
      "starshort"  => "DracinApi::Adapters::Starshort",
      "storyreel"  => "DracinApi::Adapters::Vibeshort",
      "vibeshort"  => "DracinApi::Adapters::Vibeshort",
      "vigloo"     => "DracinApi::Adapters::Vigloo",
      "vorta"      => "DracinApi::Adapters::Vorta", # hub multi-platform; slug provider = category_p
      "mola"       => "DracinApi::Adapters::Mola"   # hub Mola API (api.molatv.id); slug provider = slug platform Mola
    }.freeze
    HUBS = %w[DracinApi::Adapters::Vorta DracinApi::Adapters::Mola].freeze
    NATIVE = REGISTRY.reject { |_, v| HUBS.include?(v) }.freeze

    module_function

    def supported?(slug) = REGISTRY.key?(slug.to_s)
    def supported_slugs = REGISTRY.keys

    def for(provider, api_key: nil, lang: nil)
      klass = REGISTRY[provider.adapter_slug] or return nil
      klass.constantize.new(provider, api_key: api_key.presence || provider.effective_api_key, lang: lang)
    end

    # Adapter cadangan bila adapter utama gagal: provider DracinAPI → hub (Vorta bila kategorinya ada, lalu Mola bila
    # platformnya ada); provider hub → adapter native DracinAPI dengan slug yang sama (atau hub lain).
    def fallback_for(provider, lang: nil)
      if HUBS.include?(REGISTRY[provider.adapter_slug])
        klass = NATIVE[provider.slug]
        key = klass && (ApiSource.enabled.where.not(auth_mode: "hmac_sha256").ordered.detect { |s| !Mola.source_for?(s) }&.api_key.presence || Setting.dracin_api_key)
        return klass.constantize.new(provider, api_key: key, lang: lang) if key.present?
        provider.adapter_slug == "vorta" ? Mola.fallback_for(provider, lang: lang) : Vorta.fallback_for(provider, lang: lang)
      else
        Vorta.fallback_for(provider, lang: lang) || Mola.fallback_for(provider, lang: lang)
      end
    end
  end
end
