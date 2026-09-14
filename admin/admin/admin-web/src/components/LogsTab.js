import React, { useEffect, useMemo, useState } from "react";
import { collection, onSnapshot } from "firebase/firestore";
import { db } from "../firebase";

const formatDateTime = (value) => {
  const date = value?.toDate?.();
  if (!date) return "Pending timestamp";
  return date.toLocaleString();
};

const normalizePerformedBy = (log) => {
  const actorName = String(log?.performedBy?.name || "").trim();
  const actorRole = String(log?.performedBy?.role || "admin").trim() || "admin";
  if (actorName) return `${actorName} (${actorRole})`;

  const explicitName = String(log?.performedByName || "").trim();
  if (explicitName && explicitName.toLowerCase() !== "admin") return explicitName;

  return "Not provided";
};

const narrativeTitle = (log) => {
  if (log.actionType === "Review Removed") return "⭐ Review Removed";
  if (log.actionType === "Review Restored") return "⭐ Review Restored";
  return log.actionType || "Audit Event";
};

const narrativeDetails = (log) => {
  switch (log.actionType) {
    case "Driver Approved":
      return `${log.entityName || "Driver"} was approved and activated.`;
    case "Driver Rejected":
      return `${log.entityName || "Driver"} registration was rejected.`;
    case "Driver Deleted":
      return `${log.entityName || "Driver"} was moved to deleted records.`;
    case "Driver Restored":
      return `${log.entityName || "Driver"} was restored from deleted records.`;
    case "Parent Deleted":
      return `${log.entityName || "Parent"} was moved to deleted records.`;
    case "Parent Restored":
      return `${log.entityName || "Parent"} was restored from deleted records.`;
    case "Route Added":
      return `Route "${log.entityName || "Unnamed route"}" was added.`;
    case "Route Deleted":
      return `Route "${log.entityName || "Unnamed route"}" was moved to deleted records.`;
    case "Route Restored":
      return `Route "${log.entityName || "Unnamed route"}" was restored.`;
    case "School Added":
      return `School "${log.entityName || "Unnamed school"}" was added.`;
    case "School Deleted":
      return `School "${log.entityName || "Unnamed school"}" was moved to deleted records.`;
    case "School Restored":
      return `School "${log.entityName || "Unnamed school"}" was restored.`;
    case "Payment Status Updated":
      return "Payment status was updated to paid.";
    case "Driver Availability Updated":
      return `${log.entityName || "Driver"} seat availability was synchronized.`;
    case "Review Removed":
      return "A review was removed and moved to deleted records.";
    case "Review Restored":
      return "A review was restored back to active records.";
    default:
      return log.details || "An admin action was performed.";
  }
};

const firstNonEmptyText = (...values) => {
  for (const value of values) {
    const text = String(value ?? "").trim();
    if (text) return text;
  }
  return "";
};

const firstFiniteNumber = (...values) => {
  for (const value of values) {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) return parsed;
  }
  return null;
};

const LogsTab = ({ isSuperAdmin = false }) => {
  const [logs, setLogs] = useState([]);
  const [loading, setLoading] = useState(true);
  const [actionFilter, setActionFilter] = useState("all");
  const [dateFilter, setDateFilter] = useState("");
  const [adminFilter, setAdminFilter] = useState("all");

  useEffect(() => {
    const unsub = onSnapshot(
      collection(db, "audit_logs"),
      (snapshot) => {
        const mapped = snapshot.docs
          .map((d) => ({ id: d.id, ...d.data() }))
          .sort((a, b) => {
            const aTime = a.timestamp?.toDate?.()?.getTime?.() || 0;
            const bTime = b.timestamp?.toDate?.()?.getTime?.() || 0;
            return bTime - aTime;
          });
        setLogs(mapped);
        setLoading(false);
      },
      () => setLoading(false),
    );
    return () => unsub();
  }, []);

  const actionOptions = useMemo(
    () => ["all", ...Array.from(new Set(logs.map((log) => log.actionType).filter(Boolean)))],
    [logs],
  );

  const adminOptions = useMemo(
    () => [
      "all",
      ...Array.from(
        new Set(logs.map((log) => normalizePerformedBy(log)).filter(Boolean)),
      ),
    ],
    [logs],
  );

  const filteredLogs = useMemo(
    () =>
      logs.filter((log) => {
        if (actionFilter !== "all" && log.actionType !== actionFilter) return false;
        if (
          isSuperAdmin &&
          adminFilter !== "all" &&
          normalizePerformedBy(log) !== adminFilter
        ) {
          return false;
        }
        if (dateFilter) {
          const logDate = log.timestamp?.toDate?.();
          if (!logDate) return false;
          const dateKey = `${logDate.getFullYear()}-${String(logDate.getMonth() + 1).padStart(2, "0")}-${String(logDate.getDate()).padStart(2, "0")}`;
          if (dateKey !== dateFilter) return false;
        }
        return true;
      }),
    [actionFilter, adminFilter, dateFilter, isSuperAdmin, logs],
  );

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
          Logs
        </h1>
        <p className="text-slate-600 mt-1">Audit timeline of admin actions</p>
      </div>

      <div className="bg-white rounded-2xl p-5 shadow-lg border border-slate-100">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <select
            value={actionFilter}
            onChange={(e) => setActionFilter(e.target.value)}
            className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
          >
            {actionOptions.map((action) => (
              <option key={action} value={action}>
                {action === "all" ? "All actions" : action}
              </option>
            ))}
          </select>

          {isSuperAdmin && (
            <select
              value={adminFilter}
              onChange={(e) => setAdminFilter(e.target.value)}
              className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
            >
              {adminOptions.map((admin) => (
                <option key={admin} value={admin}>
                  {admin === "all" ? "All admins" : admin}
                </option>
              ))}
            </select>
          )}

          <input
            type="date"
            value={dateFilter}
            onChange={(e) => setDateFilter(e.target.value)}
            className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
          />
        </div>
      </div>

      <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
        {loading ? (
          <p className="text-slate-500">Loading audit logs...</p>
        ) : filteredLogs.length === 0 ? (
          <p className="text-slate-500">No logs found for selected filters.</p>
        ) : (
          <div className="space-y-4">
            {filteredLogs.map((log) => (
              <div key={log.id} className="relative pl-6">
                <span className="absolute left-0 top-1.5 h-2.5 w-2.5 rounded-full bg-emerald-500" />
                <div className="absolute left-[4px] top-5 bottom-[-14px] w-[2px] bg-slate-200" />
                <div className="bg-slate-50 border border-slate-100 rounded-xl p-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <p className="font-semibold text-slate-800">{narrativeTitle(log)}</p>
                    <span className="text-xs text-slate-500">{formatDateTime(log.timestamp)}</span>
                  </div>
                  <p className="text-sm text-slate-700 mt-2">{narrativeDetails(log)}</p>

                  {(log.actionType === "Review Removed" || log.actionType === "Review Restored") && (() => {
                    const driverName = firstNonEmptyText(log.driverName, log.reviewSnapshot?.driverName);
                    const parentName = firstNonEmptyText(log.parentName, log.reviewSnapshot?.parentName);
                    const comment = firstNonEmptyText(log.reviewText, log.reviewSnapshot?.comment);
                    const parsedRating = firstFiniteNumber(log.rating, log.reviewSnapshot?.rating);
                    return (
                      <div className="mt-3 grid grid-cols-1 md:grid-cols-2 gap-2 text-sm">
                        {driverName ? (
                          <p className="text-slate-600">
                            <span className="font-medium text-slate-700">Driver:</span> {driverName}
                          </p>
                        ) : null}
                        {parentName ? (
                          <p className="text-slate-600">
                            <span className="font-medium text-slate-700">Parent:</span> {parentName}
                          </p>
                        ) : null}
                        {parsedRating != null ? (
                          <p className="text-slate-600">
                            <span className="font-medium text-slate-700">Rating:</span> {parsedRating.toFixed(1)} ⭐
                          </p>
                        ) : null}
                        {comment ? (
                          <p className="text-slate-600 md:col-span-2 break-words">
                            <span className="font-medium text-slate-700">Comment:</span> {comment}
                          </p>
                        ) : null}
                      </div>
                    );
                  })()}

                  <p className="text-sm text-slate-600 mt-3">
                    <span className="font-medium text-slate-700">Performed By:</span>{" "}
                    {normalizePerformedBy(log)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default LogsTab;
