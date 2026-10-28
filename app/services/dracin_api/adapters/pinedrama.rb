module DracinApi
  module Adapters
    # https://pinedrama.goodbos.online — path TANPA /api; auth ?code=KEY; lang `id`→`in`
    #   /home?lang=&page=&category_id=  → { collections: [ { collection_id, title, cover, description, tags, categories, total_episodes } ], has_more }
    #   /category?lang=                 → { categories: [ { category_id, name } ] }
    #   /search?lang=&q=                → { results: [...] | nil, count }
    #   /detail?lang=&id=               → { collection_id, title, cover, description, total_episodes, episodes: [ { episode_num, video_id } ] }
    #   /episode?lang=&id=&ep=          → { best_url (MP4 H.264, tiktokcdn), quality, duration_ms, episode_num }   (param harus `ep`)
    class Pinedrama < Base
      default_host "https://pinedrama.goodbos.online"
      LANG_MAP = { "id" => "in" }.freeze

      def home
        all, trending, p2 = concurrently(-> { list(page: 1) }, -> { list(page: 1, category_id: "101") }, -> { list(page: 2) })
        [
          section(I18n.t("template.v1.sections.trending"), trending),
          section(I18n.t("template.v1.sections.latest"), all),
          section(I18n.t("template.v1.sections.for_you"), p2)
        ]
      end

      def search(q, page: 1)
        page(Array(get("/search", lang: lang, q: q, page: page)["results"]).map { |c| to_drama(c) }, page: page, has_more: false)
      end

      def detail(id)
        d = get("/detail", lang: lang, id: id)
        to_drama(d.merge("collection_id" => d["collection_id"] || id))
      end

      def episodes(id)
        Array(get("/detail", lang: lang, id: id)["episodes"]).map do |e|
          episode(number: e["episode_num"], title: "EP #{e['episode_num']}", thumbnail: nil, duration: nil, locked: false, payload: e.slice("video_id"))
        end
      end

      def play(id, ep)
        e = get("/episode", lang: lang, id: id, ep: ep)
        url = e["best_url"]
        return nil if url.blank?
        stream(url: url, episode: ep, quality: e["quality"].to_s.presence)
      end

      private
      def get(path, params = {})
        require_key!
        memo(path, params) { Http.get_json("#{host}#{path}", params: params.merge(code: api_key)) }
      end

      def list(**params) = Array(get("/home", params.merge(lang: lang))["collections"]).map { |c| to_drama(c) }

      def to_drama(c)
        tags = c["tags"].is_a?(Array) ? c["tags"] : c["categories"].to_s.split(/,\s*/)
        drama(id: c["collection_id"], title: c["title"].to_s.strip, cover: c["cover"], synopsis: c["description"], genres: tags.first(5),
              episodes: (c["total_episodes"] || c["episode_count"]).to_i.nonzero?, language: nil, rating: nil, year: nil, status: nil)
      end
    end
  end
end
