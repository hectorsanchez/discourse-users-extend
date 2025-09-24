# name: discourse-users-extend
# about: Plugin to display Discourse users and group them by country.
# version: 0.1
# authors: Héctor Sanchez

after_initialize do
  # Cache global para usuarios por país
  $users_by_country_cache = {}
  $cache_last_updated = nil
  $cache_loading = false

  # Controlador simple sin Engine
  class ::DiscourseUsersController < ::ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :check_xhr, only: [:index, :users, :debug]
    skip_before_action :preload_json, only: [:index, :users, :debug]
    skip_before_action :redirect_to_login_if_required, only: [:index, :users, :debug]
    
    def index
      # Get list of countries available from cache
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      Rails.logger.info "DISCOURSE USERS: Index request received"
      Rails.logger.info "Cache status before load: empty=#{$users_by_country_cache.empty?}, last_updated=#{$cache_last_updated}"
      
      # Load cache if empty or old
      load_cache_if_needed
      
      # Get countries from cache
      countries = $users_by_country_cache.keys.reject { |c| c == "No country" }.sort
      
      Rails.logger.info "DISCOURSE USERS: Returning #{countries.length} countries: #{countries.join(', ')}"
      
      render json: { 
        success: true, 
        countries: countries,
        total_countries: countries.length,
        cache_updated: $cache_last_updated,
        timestamp: Time.current.iso8601
      }
    end
    
    def users
      # Get users for a specific country from cache
      country = params[:country]
      
      Rails.logger.info "DISCOURSE USERS: Users request for country: '#{country}'"
      
      if country.blank?
        Rails.logger.warn "DISCOURSE USERS: Country parameter is blank"
        render json: { error: "Country parameter is required" }, status: 400
        return
      end
      
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      # Load cache if empty or old
      load_cache_if_needed
      
      # Get users from cache
      users = $users_by_country_cache[country] || []
      
      Rails.logger.info "DISCOURSE USERS: Returning #{users.length} users for country '#{country}'"
      
      render json: { 
        success: true, 
        users: users,
        country: country,
        total_users: users.length,
        cache_updated: $cache_last_updated,
        timestamp: Time.current.iso8601
      }
    end

    def save_settings
      return render json: { error: "Unauthorized" }, status: 401 unless current_user&.admin?
      
      SiteSetting.dmu_discourse_api_key = params[:dmu_discourse_api_key]
      SiteSetting.dmu_discourse_api_username = params[:dmu_discourse_api_username]
      SiteSetting.dmu_discourse_api_url = params[:dmu_discourse_api_url]
      render json: { success: true }
    end

    def debug
      # Endpoint de diagnóstico simplificado
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      Rails.logger.info "DISCOURSE USERS DEBUG: Starting simple analysis"

      begin
        # Información básica del cache actual
        cache_info = {
          cache_empty: $users_by_country_cache.empty?,
          cache_updated: $cache_last_updated,
          cache_loading: $cache_loading,
          countries_in_cache: $users_by_country_cache.keys.length,
          total_users_in_cache: $users_by_country_cache.values.flatten.length
        }
        
        # Información de configuración
        config_info = {
          api_key_present: !SiteSetting.dmu_discourse_api_key.blank?,
          api_username_present: !SiteSetting.dmu_discourse_api_username.blank?,
          api_url: SiteSetting.dmu_discourse_api_url
        }
        
        # Distribución por países
        country_distribution = {}
        $users_by_country_cache.each do |country, users|
          country_distribution[country] = users.length
        end
        
        # Debug: Show sample data from groups endpoint
        sample_groups_data = nil
        if !$users_by_country_cache.empty?
          sample_user = $users_by_country_cache.values.flatten.first
          sample_groups_data = {
            sample_user: sample_user,
            available_fields: sample_user.keys
          }
        end
        
        render json: {
          success: true,
          timestamp: Time.current.iso8601,
          cache_info: cache_info,
          config_info: config_info,
          country_distribution: country_distribution,
          sample_data: sample_groups_data,
          message: "Debug endpoint working - check cache status and configuration"
        }
        
      rescue => e
        Rails.logger.error "DISCOURSE USERS DEBUG ERROR: #{e.message}"
        render json: { 
          error: "Debug failed: #{e.message}",
          backtrace: e.backtrace.first(5)
        }, status: 500
                  end
                end
                
    private
    
    def load_cache_if_needed
      # Load cache if empty or older than 1 hour
      cache_empty = $users_by_country_cache.empty?
      cache_old = $cache_last_updated.nil? || (Time.current - $cache_last_updated) > 1.hour
      cache_loading = $cache_loading
      
      Rails.logger.info "DISCOURSE USERS: Cache check - empty=#{cache_empty}, old=#{cache_old}, loading=#{cache_loading}"
      
      if cache_empty || cache_old || cache_loading
        if cache_loading
          Rails.logger.info "DISCOURSE USERS: Cache is already loading, skipping"
          return # Already loading
        end
        
        Rails.logger.info "DISCOURSE USERS: Cache needs loading - starting load process"
        $cache_loading = true
        begin
          load_users_cache
        ensure
          $cache_loading = false
          Rails.logger.info "DISCOURSE USERS: Cache loading process completed"
        end
      else
        Rails.logger.info "DISCOURSE USERS: Cache is fresh, no loading needed"
      end
    end

    def load_users_cache
      Rails.logger.info "=== DISCOURSE USERS CACHE - STARTING LOAD ==="
      Rails.logger.info "Cache status: empty=#{$users_by_country_cache.empty?}, last_updated=#{$cache_last_updated}, loading=#{$cache_loading}"
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      Rails.logger.info "API Configuration: key_present=#{!api_key.blank?}, username_present=#{!api_username.blank?}, url=#{discourse_url}"
      
      if api_key.blank? || discourse_url.blank?
        Rails.logger.error "DISCOURSE USERS CACHE ERROR: API Key and Discourse URL not configured properly"
          return
      end
      
      # Use groups endpoint to get ALL users (more complete than directory)
      all_users = []
      
      # Get users from trust level groups (covers all users)
      trust_levels = ['trust_level_0', 'trust_level_1', 'trust_level_2', 'trust_level_3', 'trust_level_4']
      
      trust_levels.each do |trust_level|
        # Use higher limit and pagination
        offset = 0
        limit = 1000
        total_fetched = 0
        
        Rails.logger.info "Fetching users from trust level: #{trust_level}"
        
        loop do
          groups_url = "#{discourse_url}/groups/#{trust_level}/members.json?limit=#{limit}&offset=#{offset}"
          Rails.logger.info "Fetching from: #{groups_url}"
          
          require 'net/http'
          require 'uri'
          require 'json'
          
          uri = URI(groups_url)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true if uri.scheme == 'https'
          http.read_timeout = 30
          
          request = Net::HTTP::Get.new(uri)
          request['Api-Key'] = api_key
          request['Api-Username'] = api_username
          
          start_time = Time.current
          groups_response = http.request(request)
          request_time = Time.current - start_time
          
          Rails.logger.info "Trust level #{trust_level} request completed in #{request_time.round(2)}s, status: #{groups_response.code}"
          
          if groups_response.code.to_i == 200
            groups_data = JSON.parse(groups_response.body)
            users = groups_data['members'] || []
            
            if users.empty?
              Rails.logger.info "No more users for trust level #{trust_level}, breaking loop"
              break
            end
            
            # Debug: Log sample user data from groups endpoint
            if offset == 0 && users.any?
              sample_user = users.first
              Rails.logger.info "SAMPLE USER FROM GROUPS: #{sample_user.inspect}"
              Rails.logger.info "Available fields in groups response: #{sample_user.keys}"
            end
            
            all_users.concat(users)
            total_fetched += users.length
            offset += limit
            
            Rails.logger.info "Trust level #{trust_level}: #{users.length} users added (total for this level: #{total_fetched})"
            
            # If we got less than the limit, we've reached the end
            if users.length < limit
              Rails.logger.info "Reached end of users for trust level #{trust_level}"
              break
            end
            
          else
            Rails.logger.warn "Failed to get users for trust level #{trust_level}: #{groups_response.code} - #{groups_response.body[0..200]}"
            break
          end
          
          sleep(0.3) # Small delay to avoid rate limiting
        end
        
        Rails.logger.info "Completed trust level #{trust_level}: #{total_fetched} users"
      end
      
      # Remove duplicates based on username
      unique_users = all_users.uniq { |u| u['username'] }
      Rails.logger.info "Groups fetch complete: #{all_users.length} total users, #{unique_users.length} unique users"
      
      # Process users and group by country
      $users_by_country_cache = {}
      processed_count = 0
      error_count = 0
      countries_found = Set.new
      
      Rails.logger.info "Starting individual user data processing for #{unique_users.length} users..."
      
      unique_users.each_with_index do |user_data, index|
        begin
          username = user_data['username']
          
          # Get individual user data for location
          user_url = "#{discourse_url}/users/#{username}.json"
          user_uri = URI(user_url)
          user_http = Net::HTTP.new(user_uri.host, user_uri.port)
          user_http.use_ssl = true if user_uri.scheme == 'https'
          user_http.read_timeout = 30
          
          user_request = Net::HTTP::Get.new(user_uri)
          user_request['Api-Key'] = api_key
          user_request['Api-Username'] = api_username
          
          user_response = user_http.request(user_request)
          
          if user_response.code.to_i == 200
            full_user_data = JSON.parse(user_response.body)['user']
            location = full_user_data['location'] || ""
            
            # Extract country
            user_country = "No country"
            if location.present?
              if location.include?(',')
                user_country = location.split(',').last.strip
              else
                user_country = location.strip
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
              country: user_country,
              trust_level: user_data['trust_level'],
              avatar_template: user_data['avatar_template']
            }
            
            # Add to cache by country
            $users_by_country_cache[user_country] ||= []
            $users_by_country_cache[user_country] << processed_user
            countries_found.add(user_country)
            processed_count += 1
            
            # Log progress every 100 users
            if (index + 1) % 100 == 0
              Rails.logger.info "Progress: #{index + 1}/#{unique_users.length} users processed, #{countries_found.size} countries found"
            end
          else
            Rails.logger.warn "Failed to get user data for #{username}: #{user_response.code}"
            error_count += 1
          end
          
          sleep(0.05) # Reduced delay since we have more users
        rescue => e
          Rails.logger.error "Error processing user #{username}: #{e.message}"
          error_count += 1
        end
      end

      $cache_last_updated = Time.current
      Rails.logger.info "=== DISCOURSE USERS CACHE - LOAD COMPLETE ==="
      Rails.logger.info "Cache loaded successfully:"
      Rails.logger.info "  - Countries found: #{countries_found.size} (#{countries_found.to_a.sort.join(', ')})"
      Rails.logger.info "  - Users processed: #{processed_count}"
      Rails.logger.info "  - Errors encountered: #{error_count}"
      Rails.logger.info "  - Cache timestamp: #{$cache_last_updated}"
      
      # Log country distribution
      $users_by_country_cache.each do |country, users|
        Rails.logger.info "  - #{country}: #{users.length} users"
      end
    end

    
  end

  # Registrar las rutas
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#index'  # Get list of countries
    get '/discourse/users/debug' => 'discourse_users#debug'  # Debug endpoint for analysis (MUST be before :country)
    get '/discourse/users/:country' => 'discourse_users#users'  # Get users by country
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end