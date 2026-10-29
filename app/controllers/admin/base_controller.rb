class Admin::BaseController < ApplicationController
  allow_browser versions: :modern
  before_action :require_admin!
end
