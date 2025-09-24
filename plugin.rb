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
      # Get list of countries available
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
        # Use directory endpoint to get usernames, then fetch individual user data
        # Directory endpoint doesn't include location field, so we need individual calls
        directory_url = "#{discourse_url}/directory_items.json?order=created&period=all&asc=true"
        
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
          users = directory_data['directory_items'] || []
          
          Rails.logger.info "Got #{users.length} users from directory"
          
          # Get individual user data to access location field
          unique_users = []
          users.each_with_index do |user_item, index|
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
                unique_users << { 'user' => user_data }
                Rails.logger.info "User #{index + 1}/#{users.length}: #{username} - location: '#{user_data['location']}'"
              else
                Rails.logger.warn "Failed to get user #{username}: #{user_response.code}"
              end
              
              # Small delay to avoid rate limiting
              sleep(0.1)
            rescue => e
              Rails.logger.error "Error processing user #{username}: #{e.message}"
            end
          end
        else
          Rails.logger.error "Failed to get directory: #{directory_response.code}"
          unique_users = []
        end
        
        Rails.logger.info "=== DISCOURSE USERS DEBUG ==="
        Rails.logger.info "Total unique users collected: #{unique_users.length}"
        
        # Process users to extract countries
        countries_set = Set.new
        
        # Debug: Check what fields are available in user data
        Rails.logger.info "=== CHECKING AVAILABLE USER FIELDS ==="
        if unique_users.any?
          sample_user = unique_users.first['user']
          Rails.logger.info "Available fields in user data: #{sample_user.keys}"
          Rails.logger.info "Sample user data: #{sample_user.inspect}"
        end
        
        # Extract countries from location field
        unique_users.each do |user_item|
          begin
            user_data = user_item['user']
                location = user_data['location'] || ""
                
            Rails.logger.info "User #{user_data['username']}: location='#{location}'"
                
            # Extract country from location
                if location.present?
                  if location.include?(',')
                    country = location.split(',').last.strip
                  else
                    country = location.strip
              end
              
              Rails.logger.info "  -> Extracted country: '#{country}'"
              
              if country.present? && country != "No country" && country.length > 2
                countries_set.add(country)
                Rails.logger.info "  -> Added to countries set: '#{country}'"
              else
                Rails.logger.info "  -> Skipped country: '#{country}' (empty, too short, or 'No country')"
              end
            else
              Rails.logger.info "  -> No location data"
            end
          rescue => e
            Rails.logger.error "Error processing user #{user_item['user']['username']}: #{e.message}"
          end
        end
        
        countries = countries_set.to_a.sort
        
        # Debug: Show first few users' data structure
        Rails.logger.info "=== DEBUGGING USER DATA STRUCTURE ==="
        unique_users.first(3).each_with_index do |user_item, index|
          Rails.logger.info "User #{index + 1} full data: #{user_item.inspect}"
        end
        
        Rails.logger.info "Final countries list: #{countries}"
        
        # Debug: Show sample user data in response
        sample_users = unique_users.first(3).map do |user_item|
          user_data = user_item['user']
          {
            username: user_data['username'],
            location: user_data['location'],
            name: user_data['name'],
            bio: user_data['bio_raw'] || user_data['bio'] || "",
            available_fields: user_data.keys
          }
        end
        
        render json: { 
          success: true, 
          countries: countries,
          total_countries: countries.length,
          total_users_checked: unique_users.length,
          debug_info: {
            sample_users: sample_users,
            countries_found: countries,
            users_with_location: unique_users.count { |u| u['user']['location'].present? }
          },
          timestamp: Time.current.iso8601
        }
      rescue => e
        render json: { error: "Error: #{e.message}" }
      end
    end
    
    def users
      # Get users for a specific country
      country = params[:country]
      
      if country.blank?
        render json: { error: "Country parameter is required" }, status: 400
        return
      end
      
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
        # Use the same approach that worked for getting countries list
        # Get users from multiple time periods to get better coverage
        all_users = []
        
        # Get users from different time periods to get better coverage
        periods = ['all', 'yearly', 'monthly', 'weekly', 'daily']
        
        periods.each do |period|
          directory_url = "#{discourse_url}/directory_items.json?order=created&period=#{period}&asc=true"
        
          # Make request for this period
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
            users = directory_data['directory_items'] || []
            all_users.concat(users)
            Rails.logger.info "Period #{period}: #{users.length} users"
          else
            Rails.logger.warn "Failed to get users for period #{period}: #{directory_response.code}"
          end
          
          # Small delay to avoid rate limiting
          sleep(0.5)
        end
        
        # Remove duplicates based on username
        unique_users = all_users.uniq { |u| u['user']['username'] }
        
        Rails.logger.info "Total unique users collected: #{unique_users.length}"
        
        # Get individual user data to access location field and filter by country
        processed_users = []
        unique_users.each do |user_item|
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
              
              Rails.logger.info "User #{username}: location='#{location}' -> country='#{user_country}'"
              
              # Only process if country matches
              if user_country == country
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
                
                processed_users << processed_user
                Rails.logger.info "  -> Added user #{username} from #{country}"
              end
            else
              Rails.logger.warn "Failed to get user data for #{username}: #{user_response.code}"
            end
            
            # Small delay to avoid rate limiting
            sleep(0.1)
          rescue => e
            Rails.logger.error "Error processing user #{username}: #{e.message}"
          end
        end
        
        # Debug: Show sample users and their countries
        sample_users_debug = unique_users.first(5).map do |user_item|
          username = user_item['user']['username']
          # Get a quick sample of user data
          begin
            user_url = "#{discourse_url}/users/#{username}.json"
            user_uri = URI(user_url)
            user_http = Net::HTTP.new(user_uri.host, user_uri.port)
            user_http.use_ssl = true if user_uri.scheme == 'https'
            user_http.read_timeout = 10
            
            user_request = Net::HTTP::Get.new(user_uri)
            user_request['Api-Key'] = api_key
            user_request['Api-Username'] = api_username
            
            user_response = user_http.request(user_request)
            
            if user_response.code.to_i == 200
              user_data = JSON.parse(user_response.body)['user']
              location = user_data['location'] || ""
              user_country = "No country"
              if location.present?
                if location.include?(',')
                  user_country = location.split(',').last.strip
                else
                  user_country = location.strip
                end
              end
              {
                username: username,
                location: location,
                country: user_country,
                matches_target: user_country == country
              }
            else
              { username: username, error: "Failed to get user data" }
            end
          rescue => e
            { username: username, error: e.message }
          end
        end
        
        render json: { 
          success: true, 
          users: processed_users,
          country: country,
          total_users: processed_users.length,
          debug_info: {
            total_users_checked: unique_users.length,
            sample_users: sample_users_debug,
            target_country: country
          },
          timestamp: Time.current.iso8601
        }
      rescue => e
        render json: { error: "Error: #{e.message}" }
      end
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
    get '/discourse/users' => 'discourse_users#index'  # Get list of countries
    get '/discourse/users/:country' => 'discourse_users#users'  # Get users by country
    post '/discourse/save_settings' => 'discourse_users#save_settings'
  end
end