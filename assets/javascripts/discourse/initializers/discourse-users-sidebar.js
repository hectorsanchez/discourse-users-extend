import { withPluginApi } from "discourse/lib/plugin-api";

export default {
  name: "discourse-users-sidebar",
  initialize() {
    withPluginApi("0.8.31", api => {
      // Add link to sidebar
      //api.addCommunitySectionLink({
      //  name: "discourse-users",
      //  route: "discovery.latest",
      //  title: "View Discourse users grouped by country",
      //  text: "Discourse Users",
      //  icon: "users"
      //});

      // Intercept click on sidebar link
      api.onPageChange(() => {
        // Only process if we're on specific pages
        const currentPath = window.location.pathname || "";
        // Match /discourse/users with optional trailing slash or query/hash
        const isDiscourseUsersPage = /\/discourse\/users\/?(.*)?$/.test(currentPath);
        
        if (isDiscourseUsersPage) {
          // Hide any Discourse error banners/content before rendering our UI
          const errorContainers = document.querySelectorAll('.not-found-container, .page-not-found, .topic-error, .container .dialog-content');
          errorContainers.forEach((el) => (el.style.display = 'none'));
          showDiscourseUsersInterface();
        } else {
          // If we're not on user pages, ensure the interface is hidden
          hideDiscourseUsersInterface();
        }
      });
    });
  }
};

function showDiscourseUsersInterface() {
  // Check if interface already exists
  if (document.querySelector('.discourse-users-interface')) {
    return;
  }

  // Hide main Discourse content
  const mainOutlet = document.getElementById('main-outlet');
  if (mainOutlet) {
    mainOutlet.style.display = 'none';
  }

  // Create interface with inline CSS
  const discourseInterface = document.createElement('div');
  discourseInterface.className = 'discourse-users-interface';
  
  discourseInterface.innerHTML = `
    <div style="max-width: 1200px; margin: 0 auto; padding: 20px;">
      <!-- Header -->
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 30px; padding-bottom: 20px; border-bottom: 1px solid var(--primary-low);">
        <div>
          <h1 style="font-size: 2em; font-weight: 600; margin: 0 0 15px 0; color: var(--primary);">👥 Users by Country</h1>
          <p style="color: var(--primary-medium); margin: 0; font-size: 1.1em;">Select a country to view its users</p>
        </div>
        <div>
          <button id="refreshButton" style="background: var(--primary); color: var(--secondary); border: none; padding: 8px 16px; border-radius: 4px; cursor: pointer;">
             Refresh
          </button>
        </div>
      </div>

      <!-- Country Selection -->
      <div style="background: #f1b643; padding: 20px; border-radius: 4px; margin-bottom: 30px;">
        <div style="display: flex; gap: 20px; align-items: end; flex-wrap: wrap;">
          <div style="display: flex; flex-direction: column; gap: 8px;">
            <label style="font-weight: 600; font-size: 0.9em; color: var(--primary);">Select a country:</label>
            <select id="countryFilter" style="padding: 8px 12px; border: 1px solid var(--primary-low); border-radius: 4px; font-size: 14px; min-width: 200px; background: var(--secondary); color: var(--primary);">
              <option value="">Choose a country...</option>
            </select>
          </div>
          
          <div style="display: flex; flex-direction: column; gap: 8px;">
            <label style="font-weight: 600; font-size: 0.9em; color: var(--primary);">Search users:</label>
            <input 
              type="text" 
              id="searchInput"
              placeholder="First name, last name, email or username..."
              style="padding: 8px 12px; border: 1px solid var(--primary-low); border-radius: 4px; font-size: 14px; min-width: 200px; background: var(--secondary); color: var(--primary);"
              disabled
            />
          </div>
        </div>
      </div>

      <!-- Users list -->
      <div id="usersContent" style="display: flex; flex-direction: column; gap: 20px;">
        <div style="text-align: center; padding: 60px 20px; color: var(--primary-medium);">
          <div style="font-size: 3em; margin-bottom: 20px;">⏳</div>
          <p>Loading Discourse users...</p>
        </div>
      </div>
    </div>
  `;

  // Replace main-outlet content completely
  if (mainOutlet) {
    // Clear existing content
    mainOutlet.innerHTML = '';
    // Add our interface
    mainOutlet.appendChild(discourseInterface);
    // Show main-outlet
    mainOutlet.style.display = 'block';
  }

  // Load users
  loadDiscourseUsers();

  // Add event listeners
  addEventListeners();
}

function hideDiscourseUsersInterface() {
  try {
    // Hide Discourse interface if it exists
    const discourseInterface = document.querySelector('.discourse-users-interface');
    if (discourseInterface && discourseInterface.parentNode) {
      discourseInterface.remove();
    }
    
    // Restore main Discourse content
    const mainOutlet = document.getElementById('main-outlet');
    if (mainOutlet) {
      mainOutlet.style.display = 'block';
      // Force refresh if necessary
      if (mainOutlet.children.length === 0) {
        // If main-outlet is empty, Discourse may need to reload
        window.location.reload();
      }
    }
  } catch (e) {
    console.warn('Error hiding Discourse interface:', e);
    // In case of error, ensure main content is visible
    const mainOutlet = document.getElementById('main-outlet');
    if (mainOutlet) {
      mainOutlet.style.display = 'block';
    }
  }
}

// Global variables for state
let allUsers = {};
let allCountries = [];

async function loadDiscourseUsers() {
  console.log("=== SIDEBAR DEBUG - LOADING COUNTRIES ===");
  try {
    console.log("Fetching countries from /discourse/users");
    const response = await fetch('/discourse/users');
    console.log("Response status:", response.status);
    console.log("Response ok:", response.ok);
    
    const data = await response.json();
    console.log("=== SIDEBAR DEBUG - API RESPONSE ===");
    console.log("Data received:", data);
    
    if (data.success && data.countries) {
      console.log("Success response, countries found:", data.countries);
      allCountries = data.countries;
      
      populateCountryFilter();
      showCountrySelection();
    } else {
      console.error("Error response or unexpected data format:", data);
      showError(data.error || 'Error loading countries');
    }
  } catch (error) {
    console.error("=== SIDEBAR DEBUG - ERROR ===");
    console.error("Error:", error);
    console.error("Error message:", error.message);
    showError('Connection error: ' + error.message);
  }
}

function updateStats(data) {
  const totalElement = document.getElementById('totalUsers');
  const countriesElement = document.getElementById('totalCountries');
  
  if (totalElement) totalElement.textContent = data.total_users;
  if (countriesElement) countriesElement.textContent = allCountries.length;
}

function populateCountryFilter() {
  const select = document.getElementById('countryFilter');
  if (!select) return;
  
  select.innerHTML = '<option value="">Choose a country...</option>';
  
  allCountries.forEach(country => {
    const option = document.createElement('option');
    option.value = country;
    option.textContent = country;
    select.appendChild(option);
  });
}

function showCountrySelection() {
  const content = document.getElementById('usersContent');
  if (!content) return;
  
  content.innerHTML = `
    <div style="text-align: center; padding: 60px 20px; color: var(--primary-medium);">
      <div style="font-size: 4em; margin-bottom: 20px;">🌍</div>
      <h3 style="margin: 0 0 10px 0; color: var(--primary);">Select a Country</h3>
      <p style="margin: 0; font-size: 1.1em;">Choose a country from the dropdown above to view its users.</p>
    </div>
  `;
}

async function loadUsersByCountry(country) {
  console.log("=== SIDEBAR DEBUG - LOADING USERS FOR COUNTRY ===", country);
  try {
    console.log(`Fetching users for country: ${country}`);
    const response = await fetch(`/discourse/users/${encodeURIComponent(country)}`);
    console.log("Response status:", response.status);
    console.log("Response ok:", response.ok);
    
    const data = await response.json();
    console.log("=== SIDEBAR DEBUG - USERS RESPONSE ===");
    console.log("Data received:", data);
    
    if (data.success && data.users) {
      console.log("Success response, users found:", data.users.length);
      allUsers = { [country]: data.users };
      
      displayUsers(allUsers);
      enableSearch();
    } else {
      console.error("Error response or unexpected data format:", data);
      showError(data.error || 'Error loading users for this country');
    }
  } catch (error) {
    console.error("=== SIDEBAR DEBUG - ERROR ===");
    console.error("Error:", error);
    console.error("Error message:", error.message);
    showError('Connection error: ' + error.message);
  }
}

function enableSearch() {
  const searchInput = document.getElementById('searchInput');
  if (searchInput) {
    searchInput.disabled = false;
    searchInput.placeholder = "Search users in this country...";
  }
}

function filterUsers() {
  const searchInput = document.getElementById('searchInput');
  
  if (!searchInput) return;
  
  const searchTerm = searchInput.value.toLowerCase();
  
  if (!searchTerm) {
    // If no search term, show all users for the selected country
    const countryFilter = document.getElementById('countryFilter');
    const selectedCountry = countryFilter ? countryFilter.value : '';
    if (selectedCountry && allUsers[selectedCountry]) {
      displayUsers({ [selectedCountry]: allUsers[selectedCountry] });
    }
    return;
  }
  
  let filteredUsers = {};
  
  Object.keys(allUsers).forEach(country => {
    const countryUsers = allUsers[country];
    
    // Safety check: ensure countryUsers is an array
    if (!Array.isArray(countryUsers)) {
      console.warn(`Country ${country} data is not an array during filtering:`, countryUsers);
      return;
    }
    
    const filteredCountryUsers = countryUsers.filter(user => 
      (user.firstname && user.firstname.toLowerCase().includes(searchTerm)) ||
      (user.lastname && user.lastname.toLowerCase().includes(searchTerm)) ||
      (user.email && user.email.toLowerCase().includes(searchTerm)) ||
      (user.username && user.username.toLowerCase().includes(searchTerm)) ||
      (user.country && user.country.toLowerCase().includes(searchTerm)) ||
      (user.location && user.location.toLowerCase().includes(searchTerm))
    );
    
    if (filteredCountryUsers.length > 0) {
      filteredUsers[country] = filteredCountryUsers;
    }
  });
  
  displayUsers(filteredUsers);
}

function displayUsers(users) {
  const content = document.getElementById('usersContent');
  if (!content) return;
  
  if (Object.keys(users).length === 0) {
    content.innerHTML = `
      <div style="text-align: center; padding: 60px 20px; color: var(--primary-medium);">
        <div style="font-size: 4em; margin-bottom: 20px;">🔍</div>
        <h3 style="margin: 0 0 10px 0; color: var(--primary);">No users found</h3>
        <p style="margin: 0; font-size: 1.1em;">Try adjusting the filters or search with different terms.</p>
      </div>
    `;
    return;
  }
  
  let html = '';
  
  Object.keys(users).forEach(country => {
    const countryUsers = users[country];
    
    // Safety check: ensure countryUsers is an array
    if (!Array.isArray(countryUsers)) {
      console.warn(`Country ${country} data is not an array:`, countryUsers);
      return;
    }
    
    const countryDisplay = country === 'No country' ? '🌍 No country specified' : country;
    
    html += `
      <div style="background: var(--secondary); border: 1px solid var(--primary-low); border-radius: 4px; overflow: hidden;">
        <div style="display: flex; justify-content: space-between; align-items: center; padding: 15px 20px; background: #f1b643; border-bottom: 1px solid var(--primary-low);">
          <h3 style="font-size: 1.2em; font-weight: 600; margin: 0; color: var(--primary);">${countryDisplay}</h3>
          <span style="background: var(--primary); color: var(--secondary); padding: 4px 10px; border-radius: 12px; font-size: 0.9em; font-weight: 600;">${countryUsers.length} users</span>
        </div>
        
        <div style="display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 10px; padding: 20px;">
          ${countryUsers.map((user, index) => `
            <div style="display: flex; align-items: center; gap: 15px; padding: 15px; background: var(--secondary); border: 1px solid var(--primary-low); border-radius: 4px;">
              <div style="flex-shrink: 0;">
                ${user.avatar_template ? 
                  `<img data-avatar-src="${user.avatar_template.replace('{size}', '48')}" data-user-index="${index}" data-user-initials="${getInitials(user.firstname, user.lastname)}" alt="Avatar" style="width: 48px; height: 48px; border-radius: 50%; object-fit: cover; display: none;">
                   <div data-fallback-avatar="${index}" style="width: 48px; height: 48px; border-radius: 50%; background: var(--primary); color: var(--secondary); display: flex; align-items: center; justify-content: center; font-weight: 600; font-size: 1.2em;">
                   ${getInitials(user.firstname, user.lastname)}
                   </div>` :
                  `<div style="width: 48px; height: 48px; border-radius: 50%; background: var(--primary); color: var(--secondary); display: flex; align-items: center; justify-content: center; font-weight: 600; font-size: 1.2em;">
                  ${getInitials(user.firstname, user.lastname)}
                  </div>`
                }
              </div>
              <div style="flex: 1; min-width: 0;">
                <div style="font-weight: 600; margin-bottom: 3px; font-size: 1.1em; color: var(--primary);">${user.firstname} ${user.lastname}</div>
                <div style="color: var(--primary); font-size: 0.85em; font-weight: 500; margin-bottom: 3px;">
                  <a href="https://discourse.youth-care.eu/u/${user.username}" target="_blank" style="color: var(--primary); text-decoration: none;">@${user.username}</a>
                </div>
                <div style="color: var(--primary-medium); font-size: 0.85em; font-weight: 500; margin-bottom: 3px;">Location: ${user.location || user.country}</div>
                <div style="color: var(--primary-low); font-size: 0.8em;">Level: ${user.trust_level}</div>
              </div>
            </div>
          `).join('')}
        </div>
      </div>
    `;
  });
  
  content.innerHTML = html;
  
  // Initialize lazy loading for avatars
  initializeAvatarLoading();
}

function getInitials(firstname, lastname) {
  const first = firstname ? firstname.charAt(0).toUpperCase() : '';
  const last = lastname ? lastname.charAt(0).toUpperCase() : '';
  return first + last || '?';
}

// Avatar loading management
let avatarLoadQueue = [];
let isAvatarLoading = false;
const AVATAR_BATCH_SIZE = 3; // Reduced from 10 to 3
const AVATAR_LOAD_DELAY = 1000; // Increased from 200ms to 1000ms (1 second)
const AVATAR_INDIVIDUAL_DELAY = 200; // Delay between individual avatars in a batch

function initializeAvatarLoading() {
  // Collect all avatar images that need to be loaded
  const avatarImages = document.querySelectorAll('img[data-avatar-src]');
  avatarLoadQueue = Array.from(avatarImages);
  
  console.log(`Found ${avatarLoadQueue.length} avatars to load`);
  
  // Start loading avatars in batches
  loadAvatarsInBatches();
}

function loadAvatarsInBatches() {
  if (isAvatarLoading || avatarLoadQueue.length === 0) {
    return;
  }
  
  isAvatarLoading = true;
  
  // Take a batch of avatars
  const batch = avatarLoadQueue.splice(0, AVATAR_BATCH_SIZE);
  
  console.log(`Loading batch of ${batch.length} avatars`);
  
  // Load each avatar in the batch
  batch.forEach((img, index) => {
    setTimeout(() => {
      loadSingleAvatar(img);
    }, index * AVATAR_INDIVIDUAL_DELAY); // Use the new delay constant
  });
  
  // Schedule next batch
  setTimeout(() => {
    isAvatarLoading = false;
    if (avatarLoadQueue.length > 0) {
      loadAvatarsInBatches();
    }
  }, AVATAR_LOAD_DELAY);
}

function loadSingleAvatar(img) {
  const src = img.getAttribute('data-avatar-src');
  const userIndex = img.getAttribute('data-user-index');
  const fallbackDiv = document.querySelector(`[data-fallback-avatar="${userIndex}"]`);
  
  if (!src || !fallbackDiv) {
    console.warn('Missing avatar data for image:', img);
    return;
  }
  
  // Remove any existing event listeners to prevent duplicates
  img.removeEventListener('error', img._errorHandler);
  img.removeEventListener('load', img._loadHandler);
  
  // Set up error handling
  img._errorHandler = function() {
    console.log(`Avatar failed to load for user ${userIndex}, showing initials`);
    this.style.display = 'none';
    fallbackDiv.style.display = 'flex';
    fallbackDiv.style.visibility = 'visible';
    fallbackDiv.style.opacity = '1';
  };
  
  img._loadHandler = function() {
    console.log(`Avatar loaded successfully for user ${userIndex}`);
    this.style.display = 'block';
    fallbackDiv.style.display = 'none';
    fallbackDiv.style.visibility = 'hidden';
    fallbackDiv.style.opacity = '0';
  };
  
  img.addEventListener('error', img._errorHandler);
  img.addEventListener('load', img._loadHandler);
  
  // Initially hide the fallback div and show the image
  fallbackDiv.style.display = 'none';
  fallbackDiv.style.visibility = 'hidden';
  fallbackDiv.style.opacity = '0';
  img.style.display = 'block';
  
  // Check if image is already loaded
  if (img.complete && img.naturalHeight !== 0) {
    console.log(`Avatar already loaded for user ${userIndex}`);
    img._loadHandler();
    return;
  }
  
  // Set the source to trigger loading
  img.src = src;
}

function clearFilters() {
  const countryFilter = document.getElementById('countryFilter');
  const searchInput = document.getElementById('searchInput');
  
  if (countryFilter) countryFilter.value = '';
  if (searchInput) {
    searchInput.value = '';
    searchInput.disabled = true;
    searchInput.placeholder = "First name, last name, email or username...";
  }
  
  showCountrySelection();
}

function showError(message) {
  const content = document.getElementById('usersContent');
  if (!content) return;
  
  content.innerHTML = `
    <div style="text-align: center; padding: 60px 20px; color: var(--danger);">
      <div style="font-size: 4em; margin-bottom: 20px;">❌</div>
      <h3 style="margin: 0 0 10px 0; color: var(--danger);">Error</h3>
      <p style="margin: 0; font-size: 1.1em;">${message}</p>
    </div>
  `;
}

function addEventListeners() {
  // Refresh button
  const refreshButton = document.getElementById('refreshButton');
  if (refreshButton) {
    refreshButton.addEventListener('click', loadDiscourseUsers);
  }
  
  // Country filter
  const countryFilter = document.getElementById('countryFilter');
  if (countryFilter) {
    countryFilter.addEventListener('change', function() {
      const selectedCountry = this.value;
      if (selectedCountry) {
        loadUsersByCountry(selectedCountry);
      } else {
        showCountrySelection();
        const searchInput = document.getElementById('searchInput');
        if (searchInput) {
          searchInput.disabled = true;
          searchInput.value = '';
        }
      }
    });
  }
  
  // Search field
  const searchInput = document.getElementById('searchInput');
  if (searchInput) {
    searchInput.addEventListener('input', filterUsers);
  }
}
