// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/galicia_local"
import topbar from "../vendor/topbar"

// Leaflet Map Hook
const LeafletMap = {
  mounted() {
    const lat = parseFloat(this.el.dataset.lat)
    const lng = parseFloat(this.el.dataset.lng)
    const name = this.el.dataset.name

    if (isNaN(lat) || isNaN(lng)) return

    // Clear loading message
    this.el.innerHTML = ""

    // Load Leaflet CSS dynamically
    if (!document.querySelector('link[href*="leaflet"]')) {
      const link = document.createElement('link')
      link.rel = 'stylesheet'
      link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'
      document.head.appendChild(link)
    }

    // Load Leaflet JS dynamically
    if (!window.L) {
      const script = document.createElement('script')
      script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
      script.onload = () => this.initMap(lat, lng, name)
      document.head.appendChild(script)
    } else {
      this.initMap(lat, lng, name)
    }
  },

  initMap(lat, lng, name) {
    const map = L.map(this.el).setView([lat, lng], 15)

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors'
    }).addTo(map)

    L.marker([lat, lng])
      .addTo(map)
      .bindPopup(name)
      .openPopup()
  }
}

// Cities Map Hook - multiple markers with clickable popups
const CitiesMap = {
  mounted() {
    const cities = JSON.parse(this.el.dataset.cities)
    if (!cities || cities.length === 0) return

    this.el.innerHTML = ""

    // Load Leaflet CSS
    if (!document.querySelector('link[href*="leaflet"]')) {
      const link = document.createElement('link')
      link.rel = 'stylesheet'
      link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'
      document.head.appendChild(link)
    }

    // Load Leaflet JS
    if (!window.L) {
      const script = document.createElement('script')
      script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
      script.onload = () => this.initMap(cities)
      document.head.appendChild(script)
    } else {
      this.initMap(cities)
    }
  },

  initMap(cities) {
    const region = this.el.dataset.region || 'galicia'
    const regionCenters = {
      'galicia': [42.6, -8.0],
      'netherlands': [52.3, 4.9]
    }
    const defaultCenter = regionCenters[region] || [42.6, -8.0]
    const map = L.map(this.el).setView(defaultCenter, 8)

    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '© OpenStreetMap contributors'
    }).addTo(map)

    const bounds = []
    const hook = this

    cities.forEach(city => {
      if (!city.lat || !city.lng) return
      const pos = [city.lat, city.lng]
      bounds.push(pos)

      const popup = L.popup().setContent(
        `<div style="text-align:center;min-width:120px">` +
        `<strong style="font-size:14px">${city.name}</strong><br>` +
        `<span style="color:#666">${city.province}</span><br>` +
        `<span style="color:#888;font-size:12px">${city.business_count} listings</span><br>` +
        `<a href="/cities/${city.slug}" style="color:#6419e6;font-weight:600;font-size:13px">Explore →</a>` +
        `</div>`
      )

      L.marker(pos).addTo(map).bindPopup(popup)
    })

    if (bounds.length > 0) {
      map.fitBounds(bounds, { padding: [30, 30] })
    }
  }
}

// Businesses Map Hook - multiple markers with update support
const BusinessesMap = {
  mounted() {
    this.loadLeaflet(() => this.renderMap())
    this.handleEvent("update-markers", ({ businesses }) => {
      if (this.map) {
        this.updateMarkers(businesses)
      }
    })
  },

  loadLeaflet(callback) {
    if (!document.querySelector('link[href*="leaflet"]')) {
      const link = document.createElement('link')
      link.rel = 'stylesheet'
      link.href = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.css'
      document.head.appendChild(link)
    }

    if (!window.L) {
      const script = document.createElement('script')
      script.src = 'https://unpkg.com/leaflet@1.9.4/dist/leaflet.js'
      script.onload = callback
      document.head.appendChild(script)
    } else {
      callback()
    }
  },

  updateMarkers(businesses) {
    this.markersLayer.clearLayers()
    const bounds = []

    businesses.forEach(biz => {
      if (!biz.lat || !biz.lng) return
      const pos = [biz.lat, biz.lng]
      bounds.push(pos)

      const popup = L.popup().setContent(
        `<div style="min-width:140px">` +
        `<strong style="font-size:13px">${biz.name}</strong><br>` +
        `<span style="color:#666;font-size:12px">${biz.city}</span><br>` +
        (biz.address ? `<span style="color:#888;font-size:11px">${biz.address}</span><br>` : '') +
        `<a href="/businesses/${biz.id}" style="color:#6419e6;font-weight:600;font-size:12px">View details →</a>` +
        `</div>`
      )

      L.marker(pos).addTo(this.markersLayer).bindPopup(popup)
    })

    const userLat = parseFloat(this.el.dataset.userLat)
    const userLng = parseFloat(this.el.dataset.userLng)
    if (!isNaN(userLat) && !isNaN(userLng)) {
      const userIcon = L.divIcon({
        html: '<div style="background:#3b82f6;width:14px;height:14px;border-radius:50%;border:3px solid white;box-shadow:0 0 6px rgba(0,0,0,0.3)"></div>',
        iconSize: [14, 14],
        className: ''
      })
      L.marker([userLat, userLng], { icon: userIcon })
        .addTo(this.markersLayer)
        .bindPopup('You are here')
    }

    if (bounds.length > 0) {
      this.skipBoundsEvent = true
      this.map.fitBounds(bounds, { padding: [30, 30], maxZoom: 14 })
    }
  },

  renderMap() {
    const businesses = JSON.parse(this.el.dataset.businesses || '[]')
    const userLat = parseFloat(this.el.dataset.userLat)
    const userLng = parseFloat(this.el.dataset.userLng)
    const region = this.el.dataset.region || 'galicia'

    // Region center coordinates
    const regionCenters = {
      'galicia': [42.6, -8.0],
      'netherlands': [52.3, 4.9]
    }
    const defaultCenter = regionCenters[region] || [42.6, -8.0]

    if (!this.map) {
      this.el.innerHTML = ""
      this.map = L.map(this.el).setView(defaultCenter, 8)
      L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
        attribution: '© OpenStreetMap contributors'
      }).addTo(this.map)
      this.markersLayer = L.layerGroup().addTo(this.map)
      this.skipBoundsEvent = true

      this.map.on('moveend', () => {
        if (this.skipBoundsEvent) {
          this.skipBoundsEvent = false
          return
        }
        const b = this.map.getBounds()
        this.pushEvent('map_bounds', {
          south: b.getSouth(),
          north: b.getNorth(),
          west: b.getWest(),
          east: b.getEast()
        })
      })
    }

    this.markersLayer.clearLayers()
    const bounds = []

    businesses.forEach(biz => {
      if (!biz.lat || !biz.lng) return
      const pos = [biz.lat, biz.lng]
      bounds.push(pos)

      const popup = L.popup().setContent(
        `<div style="min-width:140px">` +
        `<strong style="font-size:13px">${biz.name}</strong><br>` +
        `<span style="color:#666;font-size:12px">${biz.city}</span><br>` +
        (biz.address ? `<span style="color:#888;font-size:11px">${biz.address}</span><br>` : '') +
        `<a href="/businesses/${biz.id}" style="color:#6419e6;font-weight:600;font-size:12px">View details →</a>` +
        `</div>`
      )

      L.marker(pos).addTo(this.markersLayer).bindPopup(popup)
    })

    if (!isNaN(userLat) && !isNaN(userLng)) {
      const userIcon = L.divIcon({
        html: '<div style="background:#3b82f6;width:14px;height:14px;border-radius:50%;border:3px solid white;box-shadow:0 0 6px rgba(0,0,0,0.3)"></div>',
        iconSize: [14, 14],
        className: ''
      })
      L.marker([userLat, userLng], { icon: userIcon })
        .addTo(this.markersLayer)
        .bindPopup('You are here')
      bounds.push([userLat, userLng])
    }

    if (bounds.length > 0) {
      this.skipBoundsEvent = true
      this.map.fitBounds(bounds, { padding: [30, 30], maxZoom: 14 })
    }
  }
}

// GeoLocate Hook - browser geolocation
const GeoLocate = {
  mounted() {
    this.el.addEventListener('click', () => {
      if (!navigator.geolocation) {
        this.pushEvent('location_error', { reason: 'not_supported' })
        return
      }

      this.el.classList.add('loading')

      navigator.geolocation.getCurrentPosition(
        (pos) => {
          this.el.classList.remove('loading')
          this.pushEvent('user_location', {
            lat: pos.coords.latitude,
            lng: pos.coords.longitude
          })
        },
        (err) => {
          this.el.classList.remove('loading')
          this.pushEvent('location_error', { reason: err.message })
        },
        { timeout: 10000 }
      )
    })
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, LeafletMap, CitiesMap, BusinessesMap, GeoLocate},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", _e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

