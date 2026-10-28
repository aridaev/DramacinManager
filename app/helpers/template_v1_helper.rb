module TemplateV1Helper
  POSTER_HUES = [ 352, 18, 262, 200, 158, 40, 300, 222 ].freeze

  def tv1_poster(drama, css_class: "poster", lazy: true)
    if drama.cover.present?
      hue = POSTER_HUES[drama.id.to_s.sum % POSTER_HUES.size]
      initials = drama.title.to_s.split(/\s+/).map { |w| w[0] }.join[0, 2].upcase
      image_tag drama.cover, alt: drama.title, class: css_class, loading: (lazy ? "lazy" : "eager"), decoding: "async", referrerpolicy: "no-referrer",
                data: { cover: drama.cover, hue: hue, mark: initials }
    else
      hue = POSTER_HUES[drama.id.to_s.sum % POSTER_HUES.size]
      initials = drama.title.to_s.split(/\s+/).map { |w| w[0] }.join[0, 2].upcase
      tag.div(class: [ css_class, "poster-fallback" ], style: "--hue:#{hue}", aria: { label: drama.title }) do
        tag.span(initials, class: "poster-fallback-mark") + tag.span(drama.title, class: "poster-fallback-title")
      end
    end
  end

  def tv1_drama_path(drama) = template_v1_drama_path(drama.provider, drama.id)
  def tv1_watch_path(drama, ep) = template_v1_watch_path(drama.provider, drama.id, ep)

  def tv1_episode_label(drama)
    drama.episodes ? t("template.v1.card.episodes", count: drama.episodes) : nil
  end

  # Teks per template: template.<tpl>.<key>, fallback ke template.v1.<key>.
  def tt(key, **opts)
    t("template.#{tpl}.#{key}", **opts, default: :"template.v1.#{key}")
  end

  NAV_ICONS = {
    "home"   => '<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10h5v-6h4v6h5V10"/>',
    "latest" => '<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18M8 4v5M16 4v5"/>',
    "genre"  => '<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    "search" => '<circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/>',
    "link"   => '<path d="M10 14a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-1 1"/><path d="M14 10a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l1-1"/>'
  }.freeze

  # Ikon SVG sidebar v2 berdasarkan URL item navbar.
  def tv2_nav_icon(url)
    u = url.to_s.sub(%r{\A/template/v\d}, "")
    key = if u.blank? || u == "/" then "home"
          elsif u.start_with?("/latest") then "latest"
          elsif u.start_with?("/genre") then "genre"
          elsif u.start_with?("/search") then "search"
          else "link"
          end
    tag.svg(NAV_ICONS[key].html_safe, viewBox: "0 0 24 24", width: 18, height: 18, fill: "none", stroke: "currentColor", "stroke-width": 2, "stroke-linecap": "round", "stroke-linejoin": "round", aria: { hidden: true })
  end

  SEO_TAGS = %w[h2 h3 h4 p ul ol li strong em b i a br].freeze
  # Konten SEO beranda: isi instance (HTML disanitasi) atau konten bawaan 500–800 kata.
  def tv1_seo_content_html
    raw = current_instance&.seo_content.to_s.strip
    if raw.present?
      html = raw.match?(/<\w+[^>]*>/) ? raw : simple_format(raw)
      sanitize(html, tags: SEO_TAGS, attributes: %w[href])
    else
      sanitize(t("template.v1.seo_default_html", site: tv1_site_name), tags: SEO_TAGS, attributes: %w[href])
    end
  end

  def tv1_page_title(*parts)
    [ *parts.compact_blank, t("template.v1.site_name") ].join(" · ")
  end

  # ---------- SEO per halaman (title, meta, canonical, OG, JSON-LD, teks on-page) ----------
  SEO_PAGE_KEYS = %w[home provider latest genres genre search detail watch].freeze

  def tv1_seo_page
    if controller_name == "dramas" then @drama ? (action_name == "watch" ? "watch" : "detail") : "home"
    elsif action_name == "index" then params[:provider].present? ? "provider" : "home"
    elsif SEO_PAGE_KEYS.include?(action_name) then action_name
    else "home"
    end
  end

  def tv1_site_title = current_instance&.site_title.presence || tv1_site_name

  # Keyword efektif: isian instance + otomatis "Nonton <Penyedia>", "Streaming <Penyedia>", judul drama, genre.
  def tv1_keywords
    kws = current_instance ? current_instance.seo_keyword_list : []
    prov = current_provider&.name
    if prov
      kws += [ tt("seo.kw_watch", name: prov), tt("seo.kw_stream", name: prov), tt("seo.kw_sub", name: prov) ]
    end
    kws << @drama.title if @drama
    kws << tt("seo.kw_genre", genre: tv1_genre_name(@genre)) if @genre.present?
    kws << @query if @query.present?
    kws.compact_blank.uniq.first(15)
  end

  def tv1_genre_name(g) = t("template.v1.genres.#{g}", default: g.to_s.titleize)

  def tv1_seo_title
    prov = current_provider&.name || tv1_site_name
    case tv1_seo_page
    when "home"     then current_instance&.site_title.presence || tt("seo.t_home", site: tv1_site_name)
    when "provider" then tt("seo.t_provider", provider: prov, site: tv1_site_name)
    when "latest"   then tt("seo.t_latest", provider: prov, site: tv1_site_name)
    when "genres"   then tt("seo.t_genres", site: tv1_site_name)
    when "genre"    then tt("seo.t_genre", genre: tv1_genre_name(@genre), provider: prov, site: tv1_site_name)
    when "search"   then @query.present? ? tt("seo.t_search", query: @query, site: tv1_site_name) : tt("seo.t_search_empty", site: tv1_site_name)
    when "detail"   then tt("seo.t_detail", title: @drama.title, provider: prov, site: tv1_site_name)
    when "watch"    then tt("seo.t_watch", title: @drama.title, number: @episode_number, provider: prov, site: tv1_site_name)
    end
  end

  def tv1_seo_description
    prov = current_provider&.name || tv1_site_name; site = tv1_site_name
    desc = case tv1_seo_page
           when "home"     then tv1_meta_description
           when "provider" then tt("seo.d_provider", provider: prov, site: site)
           when "latest"   then tt("seo.d_latest", provider: prov, site: site)
           when "genres"   then tt("seo.d_genres", site: site)
           when "genre"    then tt("seo.d_genre", genre: tv1_genre_name(@genre), provider: prov, site: site)
           when "search"   then tt("seo.d_search", query: @query, site: site)
           when "detail"   then @drama.synopsis.presence ? "#{@drama.title}: #{@drama.synopsis}" : tt("seo.d_detail", title: @drama.title, provider: prov, site: site)
           when "watch"    then tt("seo.d_watch", title: @drama.title, number: @episode_number, provider: prov, site: site)
           end
    desc.to_s.squish.truncate(158)
  end

  def tv1_canonical_url
    keep = tv1_seo_page == "search" ? %w[q page] : %w[page]
    q = request.query_parameters.slice(*keep).reject { |_, v| v.blank? || v == "1" }
    return request.base_url + tv1_nav_url("/nonton/#{current_provider.slug}") if tv1_seo_page == "provider" && current_provider
    request.base_url + request.path + (q.any? ? "?#{q.to_query}" : "")
  end

  def tv1_seo_image
    img = @drama&.cover.presence || tv1_logo_url.presence || tv1_icon_url
    img.to_s.start_with?("http") ? img : request.base_url + img
  end

  def tv1_seo_root_url = request.base_url + tv1_nav_url("/")

  def tv1_seo_jsonld
    site = tv1_site_name; root = tv1_seo_root_url
    graph = [ { "@type" => "WebSite", "@id" => "#{root}#website", "url" => root, "name" => site, "inLanguage" => I18n.locale.to_s,
                "potentialAction" => { "@type" => "SearchAction", "target" => "#{request.base_url}#{tv1_nav_url('/search')}?q={search_term_string}", "query-input" => "required name=search_term_string" } },
              { "@type" => "Organization", "@id" => "#{root}#org", "name" => site, "url" => root, "logo" => tv1_logo_url.presence || (request.base_url + tv1_icon_url) } ]
    crumbs = [ [ tt("nav.home"), root ] ]
    case tv1_seo_page
    when "detail", "watch"
      crumbs << [ current_provider.name, request.base_url + tv1_nav_url("/nonton/#{current_provider.slug}") ]
      crumbs << [ @drama.title, request.base_url + tv1_drama_path(@drama) ]
      series = { "@type" => "TVSeries", "@id" => "#{request.base_url}#{tv1_drama_path(@drama)}#series", "name" => @drama.title, "url" => request.base_url + tv1_drama_path(@drama),
                 "image" => @drama.cover, "description" => @drama.synopsis.to_s.truncate(300), "genre" => Array(@drama.genres).first(5), "inLanguage" => @drama.language,
                 "numberOfEpisodes" => @drama.episodes, "productionCompany" => { "@type" => "Organization", "name" => current_provider.name } }.compact
      series["aggregateRating"] = { "@type" => "AggregateRating", "ratingValue" => @drama.rating, "bestRating" => 10, "ratingCount" => 100 } if @drama.rating.to_f.positive?
      graph << series
      if tv1_seo_page == "watch"
        crumbs << [ tt("watch.title", title: @drama.title, number: @episode_number), tv1_canonical_url ]
        graph << { "@type" => "TVEpisode", "name" => tt("watch.title", title: @drama.title, number: @episode_number), "episodeNumber" => @episode_number,
                   "url" => tv1_canonical_url, "image" => @drama.cover, "partOfSeries" => { "@id" => series["@id"] } }
      end
    when "latest", "genre", "genres", "search", "provider"
      crumbs << [ tv1_seo_title.split(" · ").first, tv1_canonical_url ]
      graph << { "@type" => "CollectionPage", "name" => tv1_seo_title, "url" => tv1_canonical_url, "isPartOf" => { "@id" => "#{root}#website" } }
    end
    graph << { "@type" => "BreadcrumbList", "itemListElement" => crumbs.each_with_index.map { |(n, u), i| { "@type" => "ListItem", "position" => i + 1, "name" => n, "item" => u } } } if crumbs.size > 1
    { "@context" => "https://schema.org", "@graph" => graph }.to_json
  end

  # Teks SEO on-page untuk halaman selain beranda (menyebut penyedia, judul, keyword, dan tautan ke beranda).
  def tv1_seo_page_text_html
    page = tv1_seo_page
    return nil if page == "home"
    prov = current_provider&.name; site = tv1_site_name
    home = link_to(site, tv1_nav_url("/"))
    vars = { provider: prov, site: site, home: home, title: @drama&.title, number: @episode_number, genre: (tv1_genre_name(@genre) if @genre.present?), query: @query, episodes: @drama&.episodes }
    html = tt("seo.p_#{page}_html", **vars.compact)
    kws = tv1_keywords.first(8)
    chips = kws.map { |k| link_to(k, "#{tv1_nav_url('/search')}?q=#{ERB::Util.url_encode(k)}", class: "seo-kw", rel: "nofollow") }.join(" ").html_safe
    sanitize(html, tags: %w[p strong em a br], attributes: %w[href]) + content_tag(:p, chips, class: "seo-kws")
  end
end
