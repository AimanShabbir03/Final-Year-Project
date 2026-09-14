import React, { useEffect, useRef, useState } from "react";

const DEFAULT_CENTER = { lat: 34.1688, lng: 73.2215 }; // Abbottabad
const SEARCH_RADIUS_M = 10000; // 10 km

export default function AddSchoolMapModal({ isOpen, onClose, onSelectSchool, isAdding = false }) {
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markersRef = useRef([]);
  const circleRef = useRef(null);

  const [center, setCenter] = useState(DEFAULT_CENTER);
  const [mapReady, setMapReady] = useState(false);
  const [searchKeyword, setSearchKeyword] = useState("");
  const [searching, setSearching] = useState(false);
  const [results, setResults] = useState([]);
  const [selectedPlace, setSelectedPlace] = useState(null);
  const [locationError, setLocationError] = useState(null);

  // Get current position on open
  useEffect(() => {
    if (!isOpen) return;
    setLocationError(null);
    if (!navigator.geolocation) {
      setCenter(DEFAULT_CENTER);
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setCenter({
          lat: pos.coords.latitude,
          lng: pos.coords.longitude,
        });
      },
      () => {
        setCenter(DEFAULT_CENTER);
        setLocationError("Using default location. Enable location for accurate search.");
      },
      { enableHighAccuracy: true, timeout: 5000, maximumAge: 60000 }
    );
  }, [isOpen]);

  // Init map when open and center is set
  useEffect(() => {
    if (!isOpen || !mapRef.current || !window.google) return;

    const position = { lat: center.lat, lng: center.lng };
    if (!mapInstanceRef.current) {
      mapInstanceRef.current = new window.google.maps.Map(mapRef.current, {
        center: position,
        zoom: 13,
        mapTypeControl: true,
        streetViewControl: false,
        fullscreenControl: true,
        zoomControl: true,
      });
      setMapReady(true);
    } else {
      mapInstanceRef.current.setCenter(position);
    }

    // 10km radius circle
    if (circleRef.current) circleRef.current.setMap(null);
    circleRef.current = new window.google.maps.Circle({
      map: mapInstanceRef.current,
      center: position,
      radius: SEARCH_RADIUS_M,
      fillColor: "#059669",
      fillOpacity: 0.08,
      strokeColor: "#059669",
      strokeOpacity: 0.4,
      strokeWeight: 2,
    });
    return () => {
      if (circleRef.current) {
        circleRef.current.setMap(null);
        circleRef.current = null;
      }
    };
  }, [isOpen, center]);

  const clearMarkers = () => {
    markersRef.current.forEach((m) => m.setMap(null));
    markersRef.current = [];
  };

  const handleSearch = () => {
    const query = (searchKeyword || "school").trim();
    if (!window.google || !mapInstanceRef.current) return;

    setSearching(true);
    setResults([]);
    setSelectedPlace(null);
    clearMarkers();

    const placesService = new window.google.maps.places.PlacesService(
      mapInstanceRef.current
    );
    const request = {
      query: query,
      location: new window.google.maps.LatLng(center.lat, center.lng),
      radius: SEARCH_RADIUS_M,
    };

    placesService.textSearch(request, (searchResults, status) => {
      setSearching(false);
      if (status !== window.google.maps.places.PlacesServiceStatus.OK || !searchResults) {
        setResults([]);
        return;
      }
      const list = searchResults.map((r) => ({
        id: r.place_id,
        name: r.name,
        address: r.formatted_address || "",
        lat: r.geometry?.location?.lat(),
        lng: r.geometry?.location?.lng(),
      }));
      setResults(list);

      const bounds = new window.google.maps.LatLngBounds();
      list.forEach((place) => {
        if (place.lat != null && place.lng != null) {
          bounds.extend({ lat: place.lat, lng: place.lng });
          const marker = new window.google.maps.Marker({
            map: mapInstanceRef.current,
            position: { lat: place.lat, lng: place.lng },
            title: place.name,
          });
          marker.addListener("click", () => {
            setSelectedPlace(place);
            mapInstanceRef.current?.panTo({ lat: place.lat, lng: place.lng });
          });
          markersRef.current.push(marker);
        }
      });
      if (list.length > 0 && mapInstanceRef.current) {
        mapInstanceRef.current.fitBounds(bounds, 60);
      }
    });
  };

  const handleAddSchool = () => {
    if (!selectedPlace) return;
    onSelectSchool({
      name: selectedPlace.name,
      latitude: selectedPlace.lat,
      longitude: selectedPlace.lng,
      address: selectedPlace.address || undefined,
    });
    // Parent closes modal after successful save
  };

  const handleClose = () => {
    resetState();
    onClose();
  };

  const resetState = () => {
    setSearchKeyword("");
    setResults([]);
    setSelectedPlace(null);
    clearMarkers();
  };

  // Reset when modal closes (e.g. after successful add)
  useEffect(() => {
    if (!isOpen) resetState();
  }, [isOpen]);

  if (!isOpen) return null;

  return (
    <div
      className="fixed inset-0 z-[9998] flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="add-school-map-title"
    >
      <div
        className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm"
        onClick={handleClose}
      />
      <div
        className="relative w-full max-w-4xl max-h-[90vh] bg-white rounded-2xl shadow-2xl overflow-hidden flex flex-col"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-200 bg-gradient-to-r from-emerald-500/10 to-teal-500/10">
          <h2
            id="add-school-map-title"
            className="text-xl font-bold text-slate-800 flex items-center gap-2"
          >
            <span className="w-10 h-10 rounded-xl bg-emerald-500 text-white flex items-center justify-center">
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
            </span>
            Add school from map
          </h2>
          <button
            type="button"
            onClick={handleClose}
            className="p-2 rounded-lg hover:bg-slate-100 text-slate-600"
            aria-label="Close"
          >
            <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {locationError && (
          <div className="px-6 py-2 bg-amber-50 border-b border-amber-100 text-amber-800 text-sm">
            {locationError}
          </div>
        )}

        <div className="flex flex-col sm:flex-row flex-1 min-h-0">
          <div className="flex-1 min-h-[300px] sm:min-h-[400px] relative">
            <div ref={mapRef} className="absolute inset-0 w-full h-full" />
          </div>
          <div className="w-full sm:w-80 border-t sm:border-t-0 sm:border-l border-slate-200 flex flex-col bg-slate-50/50">
            <div className="p-4 space-y-3">
              <p className="text-xs text-slate-500 font-medium">
                Search within ~10 km of your location
              </p>
              <div className="flex gap-2">
                <input
                  type="text"
                  value={searchKeyword}
                  onChange={(e) => setSearchKeyword(e.target.value)}
                  onKeyDown={(e) => e.key === "Enter" && handleSearch()}
                  placeholder="e.g. school, high school"
                  className="flex-1 px-3 py-2.5 border border-slate-200 rounded-xl text-sm focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400"
                />
                <button
                  type="button"
                  onClick={handleSearch}
                  disabled={searching}
                  className="px-4 py-2.5 bg-emerald-500 text-white rounded-xl font-medium text-sm hover:bg-emerald-600 disabled:opacity-50"
                >
                  {searching ? "…" : "Search"}
                </button>
              </div>
            </div>
            <div className="flex-1 overflow-y-auto px-4 pb-4">
              {results.length === 0 && !searching && (
                <p className="text-slate-500 text-sm py-4">
                  Enter a keyword and click Search to find schools on the map.
                </p>
              )}
              {results.length > 0 && (
                <ul className="space-y-2">
                  {results.map((place) => (
                    <li key={place.id}>
                      <button
                        type="button"
                        onClick={() => setSelectedPlace(place)}
                        className={`w-full text-left px-3 py-2.5 rounded-xl border transition ${
                          selectedPlace?.id === place.id
                            ? "border-emerald-500 bg-emerald-50 ring-2 ring-emerald-500/30"
                            : "border-slate-200 bg-white hover:border-emerald-300 hover:bg-emerald-50/50"
                        }`}
                      >
                        <p className="font-medium text-slate-800 text-sm truncate">
                          {place.name}
                        </p>
                        {place.address && (
                          <p className="text-xs text-slate-500 truncate mt-0.5">
                            {place.address}
                          </p>
                        )}
                      </button>
                    </li>
                  ))}
                </ul>
              )}
            </div>
            {selectedPlace && (
              <div className="p-4 border-t border-slate-200 bg-white">
                <p className="text-xs text-slate-500 mb-1">Selected</p>
                <p className="font-semibold text-slate-800">{selectedPlace.name}</p>
                <p className="text-xs text-slate-500 mt-1">
                  {selectedPlace.lat?.toFixed(5)}, {selectedPlace.lng?.toFixed(5)}
                </p>
                <button
                  type="button"
                  onClick={handleAddSchool}
                  disabled={isAdding}
                  className="mt-3 w-full py-2.5 bg-emerald-500 text-white rounded-xl font-semibold text-sm hover:bg-emerald-600 disabled:opacity-70 flex items-center justify-center gap-2"
                >
                  {isAdding ? (
                    <>
                      <svg className="animate-spin w-5 h-5" fill="none" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
                      </svg>
                      Adding…
                    </>
                  ) : (
                    "Add this school"
                  )}
                </button>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
