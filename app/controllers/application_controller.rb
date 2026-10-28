class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate_user!
  around_action :switch_locale
  helper_method :admin?

  private
  def admin?
    current_user&.admin?
  end
  def require_admin!
    redirect_to root_path, alert: t("admin.access_required") unless admin?
  end
  def switch_locale(&action)
    locale = params[:locale].presence || session[:locale] || I18n.default_locale
    locale = I18n.default_locale unless I18n.available_locales.map(&:to_s).include?(locale.to_s)
    session[:locale] = locale.to_s
    I18n.with_locale(locale, &action)
  end
end
