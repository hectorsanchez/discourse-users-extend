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
    skip_before_action :check_xhr, only: [:index, :users]
    skip_before_action :preload_json, only: [:index, :users]
    skip_before_action :redirect_to_login_if_required, only: [:index, :users]
    
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
      # Endpoint de diagnóstico para verificar cobertura de usuarios
      response.headers['Content-Type'] = 'application/json'
      response.headers['Access-Control-Allow-Origin'] = '*'
      
      Rails.logger.info "DISCOURSE USERS DEBUG: Starting comprehensive user analysis"
      
      api_key = SiteSetting.dmu_discourse_api_key
      api_username = SiteSetting.dmu_discourse_api_username
      discourse_url = SiteSetting.dmu_discourse_api_url
      
      if api_key.blank? || discourse_url.blank?
        render json: { error: "API Key and Discourse URL not configured properly." }, status: 400
        return
      end

      begin
        # 1. Obtener total de usuarios desde admin endpoint
        total_users_count = get_total_users_count(discourse_url, api_key, api_username)
        
        # 2. Obtener usuarios desde múltiples fuentes
        directory_users = get_directory_users(discourse_url, api_key, api_username)
        groups_users = get_groups_users(discourse_url, api_key, api_username)
        
        # 3. Analizar cobertura
        analysis = analyze_user_coverage(directory_users, groups_users, total_users_count)
        
        # 4. Generar reporte detallado
        report = generate_debug_report(analysis, discourse_url, api_key, api_username)
        
        render json: report
        
      rescue => e
        Rails.logger.error "DISCOURSE USERS DEBUG ERROR: #{e.message}"
        render json: { error: "Debug analysis failed: #{e.message}" }, status: 500
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
      
      # Get users from multiple time periods to get better coverage
      all_users = []
      periods = ['all', 'yearly', 'monthly', 'weekly', 'daily']
      
      periods.each do |period|
        directory_url = "#{discourse_url}/directory_items.json?order=created&period=#{period}&asc=true"
        Rails.logger.info "Fetching users for period: #{period} from #{directory_url}"
        
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
        
        start_time = Time.current
        directory_response = http.request(request)
        request_time = Time.current - start_time
        
        Rails.logger.info "Period #{period} request completed in #{request_time.round(2)}s, status: #{directory_response.code}"
        
        if directory_response.code.to_i == 200
          directory_data = JSON.parse(directory_response.body)
          users = directory_data['directory_items'] || []
          all_users.concat(users)
          Rails.logger.info "Period #{period}: #{users.length} users added (total so far: #{all_users.length})"
        else
          Rails.logger.warn "Failed to get users for period #{period}: #{directory_response.code} - #{directory_response.body[0..200]}"
        end
        
        sleep(0.5) # Small delay to avoid rate limiting
      end
      
      # Remove duplicates
      unique_users = all_users.uniq { |u| u['user']['username'] }
      Rails.logger.info "Directory fetch complete: #{all_users.length} total users, #{unique_users.length} unique users"
      
      # Process users and group by country
      $users_by_country_cache = {}
      processed_count = 0
      error_count = 0
      countries_found = Set.new
      
      Rails.logger.info "Starting individual user data processing for #{unique_users.length} users..."
      
      unique_users.each_with_index do |user_item, index|
      begin
          username = user_item['user']['username']
          
          # Get individual user data
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
            user_data = JSON.parse(user_response.body)['user']
            location = user_data['location'] || ""
            
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
            
            # Log progress every 50 users
            if (index + 1) % 50 == 0
              Rails.logger.info "Progress: #{index + 1}/#{unique_users.length} users processed, #{countries_found.size} countries found"
            end
          else
            Rails.logger.warn "Failed to get user data for #{username}: #{user_response.code}"
            error_count += 1
          end
          
          sleep(0.1) # Small delay to avoid rate limiting
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

    # Métodos para diagnóstico
    def get_total_users_count(discourse_url, api_key, api_username)
      # Intentar obtener el total desde admin/stats
      admin_stats_url = "#{discourse_url}/admin/stats.json"
      
      require 'net/http'
      require 'uri'
      require 'json'
      
      uri = URI(admin_stats_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true if uri.scheme == 'https'
      http.read_timeout = 30
      
      request = Net::HTTP::Get.new(uri)
      request['Api-Key'] = api_key
      request['Api-Username'] = api_username
      
      response = http.request(request)
      
      if response.code.to_i == 200
        data = JSON.parse(response.body)
        total_users = data.dig('total_users') || data.dig('users', 'total')
        Rails.logger.info "DISCOURSE USERS DEBUG: Total users from admin stats: #{total_users}"
        return total_users
      else
        Rails.logger.warn "DISCOURSE USERS DEBUG: Could not get admin stats: #{response.code}"
        return nil
      end
    rescue => e
      Rails.logger.error "DISCOURSE USERS DEBUG: Error getting total users count: #{e.message}"
      return nil
    end

    def get_directory_users(discourse_url, api_key, api_username)
      Rails.logger.info "DISCOURSE USERS DEBUG: Getting directory users"
      all_users = []
      periods = ['all', 'yearly', 'monthly', 'weekly', 'daily']
      
      periods.each do |period|
        directory_url = "#{discourse_url}/directory_items.json?order=created&period=#{period}&asc=true"
        
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
        
        response = http.request(request)
        
        if response.code.to_i == 200
          data = JSON.parse(response.body)
          users = data['directory_items'] || []
          all_users.concat(users)
          Rails.logger.info "DISCOURSE USERS DEBUG: Period #{period}: #{users.length} users"
        else
          Rails.logger.warn "DISCOURSE USERS DEBUG: Failed period #{period}: #{response.code}"
        end
        
        sleep(0.2)
      end
      
      unique_users = all_users.uniq { |u| u['user']['username'] }
      Rails.logger.info "DISCOURSE USERS DEBUG: Directory total unique users: #{unique_users.length}"
      return unique_users
    rescue => e
      Rails.logger.error "DISCOURSE USERS DEBUG: Error getting directory users: #{e.message}"
      return []
    end

    def get_groups_users(discourse_url, api_key, api_username)
      Rails.logger.info "DISCOURSE USERS DEBUG: Getting groups users"
      all_users = []
      
      # Probar diferentes grupos
      groups = ['trust_level_0', 'trust_level_1', 'trust_level_2', 'trust_level_3', 'trust_level_4']
      
      groups.each do |group|
        groups_url = "#{discourse_url}/groups/#{group}/members.json?limit=1000&offset=0"
        
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
        
        response = http.request(request)
        
        if response.code.to_i == 200
          data = JSON.parse(response.body)
          users = data['members'] || []
          all_users.concat(users)
          Rails.logger.info "DISCOURSE USERS DEBUG: Group #{group}: #{users.length} users"
        else
          Rails.logger.warn "DISCOURSE USERS DEBUG: Failed group #{group}: #{response.code}"
        end
        
        sleep(0.2)
      end
      
      unique_users = all_users.uniq { |u| u['username'] }
      Rails.logger.info "DISCOURSE USERS DEBUG: Groups total unique users: #{unique_users.length}"
      return unique_users
    rescue => e
      Rails.logger.error "DISCOURSE USERS DEBUG: Error getting groups users: #{e.message}"
      return []
    end

    def analyze_user_coverage(directory_users, groups_users, total_users_count)
      {
        total_users_reported: total_users_count,
        directory_users_count: directory_users.length,
        groups_users_count: groups_users.length,
        directory_usernames: directory_users.map { |u| u['user']['username'] }.to_set,
        groups_usernames: groups_users.map { |u| u['username'] }.to_set,
        combined_usernames: (directory_users.map { |u| u['user']['username'] } + groups_users.map { |u| u['username'] }).to_set,
        coverage_analysis: {
          directory_only: directory_users.map { |u| u['user']['username'] }.to_set - groups_users.map { |u| u['username'] }.to_set,
          groups_only: groups_users.map { |u| u['username'] }.to_set - directory_users.map { |u| u['user']['username'] }.to_set,
          in_both: directory_users.map { |u| u['user']['username'] }.to_set & groups_users.map { |u| u['username'] }.to_set
        }
      }
    end

    def generate_debug_report(analysis, discourse_url, api_key, api_username)
      Rails.logger.info "DISCOURSE USERS DEBUG: Generating comprehensive report"
      
      {
        success: true,
        timestamp: Time.current.iso8601,
        summary: {
          total_users_in_discourse: analysis[:total_users_reported],
          users_found_in_directory: analysis[:directory_users_count],
          users_found_in_groups: analysis[:groups_users_count],
          unique_users_found: analysis[:combined_usernames].size,
          coverage_percentage: analysis[:total_users_reported] ? (analysis[:combined_usernames].size.to_f / analysis[:total_users_reported] * 100).round(2) : nil
        },
        coverage_breakdown: {
          directory_only: analysis[:coverage_analysis][:directory_only].size,
          groups_only: analysis[:coverage_analysis][:groups_only].size,
          in_both_sources: analysis[:coverage_analysis][:in_both].size
        },
        sample_users: {
          directory_sample: analysis[:directory_usernames].to_a.first(10),
          groups_sample: analysis[:groups_usernames].to_a.first(10),
          directory_only_sample: analysis[:coverage_analysis][:directory_only].to_a.first(10),
          groups_only_sample: analysis[:coverage_analysis][:groups_only].to_a.first(10)
        },
        recommendations: generate_recommendations(analysis),
        next_steps: [
          "Check if missing users have location data",
          "Verify API permissions for different endpoints",
          "Consider using search endpoint for additional coverage"
        ]
      }
    end

    def generate_recommendations(analysis)
      recommendations = []
      
      if analysis[:total_users_reported] && analysis[:combined_usernames].size < analysis[:total_users_reported]
        missing_count = analysis[:total_users_reported] - analysis[:combined_usernames].size
        recommendations << "Missing #{missing_count} users - may need additional data sources"
      end
      
      if analysis[:coverage_analysis][:groups_only].size > 0
        recommendations << "Groups endpoint found #{analysis[:coverage_analysis][:groups_only].size} users not in directory"
      end
      
      if analysis[:coverage_analysis][:directory_only].size > 0
        recommendations << "Directory endpoint found #{analysis[:coverage_analysis][:directory_only].size} users not in groups"
      end
      
      recommendations << "Consider combining both directory and groups endpoints for maximum coverage"
      
      recommendations
    end
    
  end

  # Registrar las rutas
  Discourse::Application.routes.append do
    get '/discourse/users' => 'discourse_users#index'  # Get list of countries
    get '/discourse/users/:country' => 'discourse_users#users'  # Get users by country
    get '/discourse/users/debug' => 'discourse_users#debug'  # Debug endpoint for analysis
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end