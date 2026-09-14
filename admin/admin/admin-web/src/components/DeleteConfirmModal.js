import React, { useEffect } from "react";

export default function DeleteConfirmModal({
  isOpen,
  onClose,
  onConfirm,
  title = "Delete item",
  description = "This action cannot be undone.",
  itemName,
  confirmLabel = "Delete",
  isLoading = false,
  variant = "danger", // "danger" (red) or "warning" (amber)
}) {
  useEffect(() => {
    const handleEscape = (e) => {
      if (e.key === "Escape" && !isLoading) onClose();
    };
    if (isOpen) {
      document.addEventListener("keydown", handleEscape);
      document.body.style.overflow = "hidden";
    }
    return () => {
      document.removeEventListener("keydown", handleEscape);
      document.body.style.overflow = "";
    };
  }, [isOpen, isLoading, onClose]);

  if (!isOpen) return null;

  const isDanger = variant === "danger";

  return (
    <div
      className="fixed inset-0 z-[9998] flex items-center justify-center p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="delete-modal-title"
      aria-describedby="delete-modal-desc"
    >
      {/* Backdrop */}
      <div
        className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm animate-modal-backdrop"
        onClick={isLoading ? undefined : onClose}
      />

      {/* Modal card */}
      <div
        className="relative w-full max-w-md rounded-2xl shadow-2xl overflow-hidden animate-modal-in"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="bg-white p-6 sm:p-8">
          {/* Icon */}
          <div
            className={`
              w-14 h-14 rounded-2xl flex items-center justify-center mx-auto mb-5
              ${isDanger
                ? "bg-gradient-to-br from-rose-500 to-red-600 text-white shadow-lg shadow-rose-500/30"
                : "bg-gradient-to-br from-amber-400 to-orange-500 text-white shadow-lg shadow-amber-500/30"
              }
            `}
          >
            <svg
              className="w-8 h-8"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
          </div>

          <h2
            id="delete-modal-title"
            className="text-xl font-bold text-slate-800 text-center mb-2"
          >
            {title}
          </h2>
          <p
            id="delete-modal-desc"
            className="text-slate-600 text-center text-sm leading-relaxed mb-1"
          >
            {description}
          </p>
          {itemName && (
            <p className="text-slate-800 font-semibold text-center mt-2 mb-6">
              &ldquo;{itemName}&rdquo;
            </p>
          )}
          {!itemName && <div className="h-6" />}

          <div className="flex gap-3">
            <button
              type="button"
              onClick={onClose}
              disabled={isLoading}
              className="flex-1 py-3 px-4 rounded-xl font-semibold bg-slate-100 text-slate-700 hover:bg-slate-200 transition disabled:opacity-50"
            >
              Cancel
            </button>
            <button
              type="button"
              onClick={onConfirm}
              disabled={isLoading}
              className={`
                flex-1 py-3 px-4 rounded-xl font-semibold text-white transition disabled:opacity-70
                flex items-center justify-center gap-2
                ${isDanger
                  ? "bg-gradient-to-r from-rose-500 to-red-600 hover:from-rose-600 hover:to-red-700 shadow-lg shadow-rose-500/25"
                  : "bg-gradient-to-r from-amber-500 to-orange-600 hover:from-amber-600 hover:to-orange-700 shadow-lg shadow-amber-500/25"
                }
              `}
            >
              {isLoading ? (
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
                  Deleting…
                </>
              ) : (
                confirmLabel
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
