# Kompatibilitas: Pengaturan API lama kini dikelola di Admin::ApiSourcesController.
class Admin::SettingsController < Admin::BaseController
  def edit
    source = ApiSource.default
    redirect_to(source ? edit_admin_api_source_path(source) : new_admin_api_source_path)
  end

  def update = edit

  def test_connection
    source = ApiSource.default or return redirect_to(new_admin_api_source_path)
    redirect_to test_admin_api_source_path(source), status: :temporary_redirect
  end
end
