module DracinApi
  # Registry adapter per provider. Setiap provider DracinAPI punya host dan skema API sendiri
  # (lihat field `api` di /api/status), jadi tiap provider butuh adapter.
  module Adapters
    REGISTRY = {
      "cubetv"     => "DracinApi::Adapters::Cubetv",
      "dramabite"    => "DracinApi::Adapters::Dramabite",
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
      "vigloo"     => "DracinApi::Adapters::Vigloo"
    }.freeze

    module_function

    def supported?(slug) = REGISTRY.key?(slug.to_s)
    def supported_slugs = REGISTRY.keys

    def for(provider, api_key: nil, lang: nil)
      klass = REGISTRY[provider.adapter_slug] or return nil
      klass.constantize.new(provider, api_key: api_key.presence || provider.effective_api_key, lang: lang)
    end
  end
end
