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
      "vorta"      => "DracinApi::Adapters::Vorta" # hub multi-platform; slug provider = category_p
    }.freeze
    NATIVE = REGISTRY.reject { |_, v| v == "DracinApi::Adapters::Vorta" }.freeze

    module_function

    def supported?(slug) = REGISTRY.key?(slug.to_s)
    def supported_slugs = REGISTRY.keys

    def for(provider, api_key: nil, lang: nil)
      klass = REGISTRY[provider.adapter_slug] or return nil
      klass.constantize.new(provider, api_key: api_key.presence || provider.effective_api_key, lang: lang)
    end

    # Adapter cadangan bila adapter utama gagal: provider DracinAPI → Vorta (bila kategorinya ada di hub Vorta),
    # provider Vorta → adapter native DracinAPI dengan slug yang sama.
    def fallback_for(provider, lang: nil)
      if provider.adapter_slug == "vorta"
        klass = NATIVE[provider.slug] or return nil
        key = ApiSource.enabled.where.not(auth_mode: "hmac_sha256").ordered.first&.api_key.presence || Setting.dracin_api_key
        return nil if key.blank?
        klass.constantize.new(provider, api_key: key, lang: lang)
      else
        Vorta.fallback_for(provider, lang: lang)
      end
    end
  end
end
