Rails.application.routes.draw do
  template_v1_routes = lambda do
    root "home#index"
    get "nonton/:provider", to: "home#index", as: :provider_home
    get "amp", to: "home#amp", as: :amp
    get "robots.txt", to: "/seo#robots", as: :robots
    get "sitemap.xml", to: "/seo#sitemap", as: :sitemap
    get "sitemap-:part.xml", to: "/seo#sitemap", as: :sitemap_part, constraints: { part: /[a-z0-9_-]+/ }
    get ":key.txt", to: "/seo#indexnow_key", constraints: { key: /[a-f0-9]{32}/ }
    get "search", to: "home#search"
    get "genre", to: "home#genres", as: :genres
    get "latest", to: "home#latest", as: :latest
    get "genre/:genre", to: "home#genre", as: :genre
    get "stream/:sid", to: "streams#show", as: :stream
    get "subtitle", to: "subtitles#show", as: :subtitle
    get ":provider/drama/:id", to: "dramas#show", as: :drama
    get ":provider/drama/:id/watch/:ep", to: "dramas#watch", as: :watch
    get "akun", to: "members#show", as: :member
    post "akun/login", to: "members#login", as: :member_login
    post "akun/register", to: "members#register", as: :member_register
    delete "akun/logout", to: "members#logout", as: :member_logout
    post "akun/deposit", to: "members#deposit", as: :member_deposit
    post "akun/share", to: "members#share", as: :member_share
  end

  # Domain kustom instance (tabel domains) → template instance dilayani di root host tersebut.
  constraints InstanceHost::Constraint.new do
    scope module: "template/v1", as: :site, &template_v1_routes
  end

  get "provider_logos/:slug", to: "provider_logos#show", as: :provider_logo
  get "covers", to: "covers#show", as: :cover_proxy
  get "robots.txt", to: "seo#robots"
  get ":key.txt", to: "seo#indexnow_key", constraints: { key: /[a-f0-9]{32}/ }

  devise_for :users
  root "dashboard#show"
  namespace :admin do
    root "dashboard#show"
    resources :providers, only: [ :index, :update ] do
      collection do
        patch :enable_all
        patch :disable_all
        post :unmute
        post :recheck_all
        post :sync_status
      end
      member { post :recheck }
    end
    resource :settings, only: [ :edit, :update ] do
      post :test_connection
    end
    resources :instances, only: [ :index, :show, :create, :edit, :update, :destroy ] do
      member { patch :regenerate; patch :generate_seo; get :seo_status; match :submit_indexnow, via: [ :post, :patch ] }
      resources :domains, only: [ :create, :destroy ] do
        member { post :refresh; post :retry; post :geo }
      end
      resources :members, only: [ :index, :destroy ] do
        member { post :approve; post :reject; post :grant; post :revoke }
      end
      resources :stats, only: [ :index ]
      resources :auto_posts, only: [ :index, :create, :update, :destroy ] do
        collection { get :dramas; patch :bulk_update }
        member { post :run_now; post :sync_profile }
      end
      resource :telegram, only: [ :show ], controller: "telegram" do
        post :qr_start
        get :qr_status
        post :qr_password
        post :qr_cancel
        post :logout
        post :sync_dialogs
        patch :bulk_update
        post "targets/:target_id/run_now", action: :run_now, as: :run_now_target
        delete "targets/:target_id", action: :destroy_target, as: :target
        post "targets/:target_id/promos", action: :create_promo, as: :target_promos
        post "targets/:target_id/promo_run_now", action: :promo_run_now, as: :promo_run_now_target
        patch "promos/:promo_id", action: :update_promo, as: :promo
        delete "promos/:promo_id", action: :destroy_promo
        get "promos/:promo_id/image", action: :promo_image, as: :promo_image
      end
    end
    resource :site_settings, only: [ :edit, :update ] do
      post :test_tokenplus
      delete :clear_tokenplus
      post :test_cloudflare
      delete :clear_cloudflare
      post :test_telegram
      delete :clear_telegram
    end
    resources :api_sources, except: [ :show ] do
      member do
        post :test
        post :sync
        patch :make_default
      end
    end
    resources :custom_providers, only: [ :new, :create, :edit, :update, :destroy ], controller: "custom_providers"
  end

  # Template publik v1 (tampilan ala situs streaming drama pendek, data dari DracinAPI)
  scope "template/v1", module: "template/v1", as: :template_v1, defaults: { tpl: "v1" }, &template_v1_routes
  scope "template/v2", module: "template/v1", as: :template_v2, defaults: { tpl: "v2" }, &template_v1_routes
  scope "template/v3", module: "template/v1", as: :template_v3, defaults: { tpl: "v3" }, &template_v1_routes
  scope "template/v4", module: "template/v1", as: :template_v4, defaults: { tpl: "v4" }, &template_v1_routes
end
