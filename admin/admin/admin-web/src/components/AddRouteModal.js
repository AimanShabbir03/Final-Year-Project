import React, { useState, useEffect } from "react";
import PlaceSearchModal from "./PlaceSearchModal";

export default function AddRouteModal({
  isOpen,
  onClose,
  onAddRoute,
  schools = [],
  isAdding = false,
}) {
  const [selectedSchool, setSelectedSchool] = useState(null);
  const [destination, setDestination] = useState(null);
  const [fare, setFare] = useState("");
  const [placeSearchOpen, setPlaceSearchOpen] = useState(false);

  const schoolsWithCoords = schools.filter(
    (s) => s.latitude != null && s.longitude != null
  );

  useEffect(() => {
    if (!isOpen) {
      setSelectedSchool(null);
      setDestination(null);
      setFare("");
      setPlaceSearchOpen(false);
    }
  }, [isOpen]);

  const handleSubmit = () => {
    const numericFare = Number(fare);
    if (!selectedSchool || !destination || !Number.isFinite(numericFare) || numericFare <= 0) return;
    onAddRoute({
      schoolName: selectedSchool.name,
      schoolLatitude: selectedSchool.latitude,
      schoolLongitude: selectedSchool.longitude,
      schoolId: selectedSchool.id,
      destinationName: destination.name,
      destinationLatitude: destination.latitude,
      destinationLongitude: destination.longitude,
      destinationAddress: destination.address,
      fare: numericFare,
    });
    // Parent closes modal after successful save
  };

  const handleClose = () => {
    setSelectedSchool(null);
    setDestination(null);
    setFare("");
    setPlaceSearchOpen(false);
    onClose();
  };

  if (!isOpen) return null;

  return (
    <>
      <div
        className="fixed inset-0 z-[9998] flex items-center justify-center p-4"
        role="dialog"
        aria-modal="true"
        aria-labelledby="add-route-title"
      >
        <div
          className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm"
          onClick={handleClose}
        />
        <div
          className="relative w-full max-w-lg bg-white rounded-2xl shadow-2xl overflow-hidden"
          onClick={(e) => e.stopPropagation()}
        >
          <div className="px-6 py-4 border-b border-slate-200 bg-gradient-to-r from-emerald-500/10 to-teal-500/10">
            <div className="flex items-center justify-between">
              <h2
                id="add-route-title"
                className="text-xl font-bold text-slate-800 flex items-center gap-2"
              >
                <span className="w-10 h-10 rounded-xl bg-emerald-500 text-white flex items-center justify-center">
                  <svg
                    className="w-5 h-5"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7"
                    />
                  </svg>
                </span>
                Add route
              </h2>
              <button
                type="button"
                onClick={handleClose}
                className="p-2 rounded-lg hover:bg-slate-100 text-slate-600"
                aria-label="Close"
              >
                <svg
                  className="w-6 h-6"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M6 18L18 6M6 6l12 12"
                  />
                </svg>
              </button>
            </div>
          </div>

          <div className="p-6 space-y-5">
            <p className="text-sm text-slate-600">
              Select a school and a destination. The route will be saved with names and coordinates.
            </p>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-2">
                School (origin)
              </label>
              <select
                value={selectedSchool?.id ?? ""}
                onChange={(e) => {
                  const id = e.target.value;
                  const school = schoolsWithCoords.find((s) => s.id === id) || null;
                  setSelectedSchool(school);
                }}
                className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 bg-white"
              >
                <option value="">Select a school</option>
                {schoolsWithCoords.map((s) => (
                  <option key={s.id} value={s.id}>
                    {s.name}
                    {s.latitude != null && ` (${s.latitude.toFixed(4)}, ${s.longitude.toFixed(4)})`}
                  </option>
                ))}
                {schoolsWithCoords.length === 0 && (
                  <option value="" disabled>
                    No schools with location. Add schools from map first.
                  </option>
                )}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-2">
                Destination
              </label>
              {destination ? (
                <div className="flex items-center justify-between gap-3 p-3 rounded-xl border border-emerald-200 bg-emerald-50/50">
                  <div className="min-w-0">
                    <p className="font-medium text-slate-800 truncate">{destination.name}</p>
                    <p className="text-xs text-slate-500 mt-0.5">
                      {destination.latitude?.toFixed(5)}, {destination.longitude?.toFixed(5)}
                    </p>
                  </div>
                  <div className="flex gap-2 flex-shrink-0">
                    <button
                      type="button"
                      onClick={() => setPlaceSearchOpen(true)}
                      className="px-3 py-1.5 text-sm font-medium text-emerald-700 hover:bg-emerald-100 rounded-lg transition"
                    >
                      Change
                    </button>
                    <button
                      type="button"
                      onClick={() => setDestination(null)}
                      className="px-3 py-1.5 text-sm font-medium text-slate-600 hover:bg-slate-200 rounded-lg transition"
                    >
                      Clear
                    </button>
                  </div>
                </div>
              ) : (
                <button
                  type="button"
                  onClick={() => setPlaceSearchOpen(true)}
                  className="w-full px-4 py-3 border-2 border-dashed border-slate-200 rounded-xl text-slate-600 hover:border-emerald-400 hover:bg-emerald-50/50 hover:text-emerald-700 transition flex items-center justify-center gap-2"
                >
                  <svg
                    className="w-5 h-5"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z"
                    />
                  </svg>
                  Select destination on map
                </button>
              )}
            </div>

            <div>
              <label className="block text-sm font-medium text-slate-700 mb-2">
                Fare (PKR)
              </label>
              <input
                type="number"
                min="1"
                step="0.01"
                value={fare}
                onChange={(e) => setFare(e.target.value)}
                placeholder="Enter fare"
                className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 bg-white"
              />
            </div>

            <div className="pt-2 flex gap-3">
              <button
                type="button"
                onClick={handleClose}
                className="flex-1 py-3 px-4 rounded-xl font-semibold bg-slate-100 text-slate-700 hover:bg-slate-200 transition"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={handleSubmit}
                disabled={!selectedSchool || !destination || Number(fare) <= 0 || isAdding}
                className="flex-1 py-3 px-4 rounded-xl font-semibold bg-emerald-500 text-white hover:bg-emerald-600 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2"
              >
                {isAdding ? (
                  <>
                    <svg
                      className="animate-spin w-5 h-5"
                      fill="none"
                      viewBox="0 0 24 24"
                    >
                      <circle
                        className="opacity-25"
                        cx="12"
                        cy="12"
                        r="10"
                        stroke="currentColor"
                        strokeWidth="4"
                      />
                      <path
                        className="opacity-75"
                        fill="currentColor"
                        d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
                      />
                    </svg>
                    Adding…
                  </>
                ) : (
                  "Add route"
                )}
              </button>
            </div>
          </div>
        </div>
      </div>

      <PlaceSearchModal
        isOpen={placeSearchOpen}
        onClose={() => setPlaceSearchOpen(false)}
        onSelectPlace={(place) => {
          setDestination(place);
          setPlaceSearchOpen(false);
        }}
        title="Select destination"
        initialCenter={
          selectedSchool?.latitude != null && selectedSchool?.longitude != null
            ? { lat: selectedSchool.latitude, lng: selectedSchool.longitude }
            : undefined
        }
      />
    </>
  );
}
