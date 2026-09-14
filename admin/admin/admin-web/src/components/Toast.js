import React, { useEffect } from "react";

const icons = {
  success: (
    <svg
      className="w-6 h-6 flex-shrink-0"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
        d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
  ),
  error: (
    <svg
      className="w-6 h-6 flex-shrink-0"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
    >
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="2"
        d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
      />
    </svg>
  ),
};

export default function Toast({ message, type = "success", onClose }) {
  const isSuccess = type === "success";

  useEffect(() => {
    const t = setTimeout(onClose, 4000);
    return () => clearTimeout(t);
  }, [onClose]);

  return (
    <div
      role="alert"
      className={`
        pointer-events-auto flex items-center gap-4 rounded-xl px-4 py-3.5 shadow-xl border
        animate-toast-in
        ${isSuccess
          ? "bg-gradient-to-r from-emerald-500 to-teal-600 text-white border-emerald-400/30"
          : "bg-gradient-to-r from-rose-500 to-red-600 text-white border-rose-400/30"
        }
      `}
    >
      <span className={isSuccess ? "text-emerald-100" : "text-rose-100"}>
        {icons[type]}
      </span>
      <p className="flex-1 font-medium text-sm">{message}</p>
      <button
        type="button"
        onClick={onClose}
        className="p-1 rounded-lg hover:bg-white/20 transition-colors focus:outline-none focus:ring-2 focus:ring-white/50"
        aria-label="Dismiss"
      >
        <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  );
}
