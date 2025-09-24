# name: discourse-users-extend
# about: Plugin to display Discourse users and group them by country.
# version: 0.1
# authors: Héctor Sanchez

after_initialize do
  # Controlador simple sin Engine
  class ::DiscourseUsersController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :check_xhr, only: [:index, :users]
    skip_before_action :preload_json, only: [:index, :users]
    skip_before_action :redirect_to_login_if_required, only: [:index, :users]
    
    def index
      # Simple approach like working Moodle plugin
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key and Discourse URL not configured properly." }, status: 400
        return
      end

      begin
        # Get all users using groups endpoint with pagination
        # This endpoint supports limit and offset parameters
        directory_url = "#{discourse_url}/groups/trust_level_0/members.json?limit=1000&offset=0"
        
        # Make request directly like Moodle plugin
        require 'net/http'
        require 'uri'
        require 'json'
        
        uri = URI(directory_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true if uri.scheme == 'https'
        http.read_timeout = 30
        
        request = Net::HTTP::Get.new(uri)
        request['Api-Key'] = api_key
        request['Api-Username'] = api_username
        
        directory_response = http.request(request)
        
        if directory_response.code.to_i == 200
          directory_data = JSON.parse(directory_response.body)
          # Groups endpoint returns members directly, not in directory_items
          users = directory_data['members'] || []
          
          Rails.logger.info "=== DISCOURSE USERS DEBUG ==="
          Rails.logger.info "Total users from API: #{users.length}"
          Rails.logger.info "First few users: #{users.first(3).map { |u| { username: u['username'], location: u['location'] } }}"
          
          # Process users
          processed_users = []
          success_count = 0
          error_count = 0
          users.each do |user|
            begin
              # Get complete user profile
              user_url = "#{discourse_url}/users/#{user['username']}.json"
              user_uri = URI(user_url)
              user_http = Net::HTTP.new(user_uri.host, user_uri.port)
              user_http.use_ssl = true if user_uri.scheme == 'https'
              user_http.read_timeout = 30
              
              user_request = Net::HTTP::Get.new(user_uri)
              user_request['Api-Key'] = api_key
              user_request['Api-Username'] = api_username
              
              user_response = user_http.request(user_request)
              
              if user_response.code.to_i == 200
                user_data = JSON.parse(user_response.body)['user']
                location = user_data['location'] || ""
                
                Rails.logger.info "User #{user['username']}: location='#{location}'"
                
                # Extract country
                country = "No country"
                if location.present?
                  if location.include?(',')
                    country = location.split(',').last.strip
                  else
                    country = location.strip
                  end
                end
                
                # Split name safely
                name_parts = (user_data['name'] || "").split(' ')
                firstname = name_parts.first || user_data['username']
                lastname = name_parts.drop(1).join(' ') || ""
                
                processed_user = {
                  firstname: firstname,
                  lastname: lastname,
                  email: user_data['email'],
                  username: user_data['username'],
                  location: location,
                  country: country,
                  trust_level: user_data['trust_level'],
                  avatar_template: user_data['avatar_template']
                }
                
                processed_users << processed_user
                success_count += 1
              else
                # Fallback with basic data
                Rails.logger.warn "Failed to get user data for #{user['username']}: #{user_response.code}"
                processed_user = {
                  firstname: user['username'],
                  lastname: "",
                  email: nil,
                  username: user['username'],
                  location: nil,
                  country: "No country",
                  trust_level: user['trust_level'],
                  avatar_template: user['avatar_template']
                }
                processed_users << processed_user
                error_count += 1
              end
            rescue => e
              # In case of error, use basic data
              Rails.logger.error "Error processing user #{user['username']}: #{e.message}"
              processed_user = {
                firstname: user['username'],
                lastname: "",
                email: nil,
                username: user['username'],
                location: nil,
                country: "No country",
                trust_level: user['trust_level'],
                avatar_template: user['avatar_template']
              }
              processed_users << processed_user
              error_count += 1
            end
          end
          
          Rails.logger.info "Processing complete: #{success_count} success, #{error_count} errors"
          
          # Group by country
          grouped = processed_users.group_by { |u| u[:country] }

          render json: { 
            success: true, 
            users_by_country: grouped,
            total_users: processed_users.length,
            timestamp: Time.current.iso8601
          }
        else
          render json: { error: "Failed to get directory", response: directory_response.body }
        end
      rescue => e
        render json: { error: "Error: #{e.message}" }
      end
    end
    
    def users
      # Alias for index method to maintain compatibility
      index
    end

    def save_settings
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      SiteSetting.dmu_discourse_api_key = params[:dmu_discourse_api_key]
      SiteSetting.dmu_discourse_api_username = params[:dmu_discourse_api_username]
      SiteSetting.dmu_discourse_api_url = params[:dmu_discourse_api_url]
      render json: { success: true }
    end
    
  end

  # Registrar las rutas
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#index'  # JSON data
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end