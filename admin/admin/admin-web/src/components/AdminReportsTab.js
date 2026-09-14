import React, { useEffect, useMemo, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { db } from "../firebase";

const formatDate = (value) => {
  const date = value?.toDate?.();
  if (!date) return "Not available";
  return date.toLocaleString();
};

const formatCreatedAt = (value) => {
  if (value?.toDate) return value.toDate().toLocaleDateString();
  if (value instanceof Date) return value.toLocaleDateString();
  if (typeof value === "string" || typeof value === "number") {
    const dt = new Date(value);
    if (!Number.isNaN(dt.getTime())) return dt.toLocaleDateString();
  }
  return "Not provided";
};

const toTargetLabel = (log) =>
  String(
    log?.target?.name ||
    log.entityName ||
    log.routeName ||
    log?.target?.type ||
    log.targetType ||
    "Record",
  ).trim();

const AdminReportsTab = () => {
  const [admins, setAdmins] = useState([]);
  const [logs, setLogs] = useState([]);
  const [selectedAdminId, setSelectedAdminId] = useState("all");
  const [dateFilter, setDateFilter] = useState("");

  useEffect(() => {
    const adminsQuery = query(collection(db, "users"), where("role", "==", "admin"));
    const unsubAdmins = onSnapshot(adminsQuery, (snapshot) => {
      const rows = snapshot.docs
        .map((d) => ({ id: d.id, ...d.data() }))
        .filter((admin) => admin.isDeleted !== true);
      setAdmins(rows);
    });
    return () => unsubAdmins();
  }, []);

  useEffect(() => {
    const unsubLogs = onSnapshot(collection(db, "audit_logs"), (snapshot) => {
      const rows = snapshot.docs
        .map((d) => ({ id: d.id, ...d.data() }))
        .sort((a, b) => {
          const aTime = a.timestamp?.toDate?.()?.getTime?.() || 0;
          const bTime = b.timestamp?.toDate?.()?.getTime?.() || 0;
          return bTime - aTime;
        });
      setLogs(rows);
    });
    return () => unsubLogs();
  }, []);

  const selectedAdmin = useMemo(() => {
    if (selectedAdminId === "all") return null;
    return admins.find((admin) => admin.id === selectedAdminId) || null;
  }, [admins, selectedAdminId]);

  const filteredLogs = useMemo(
    () =>
      logs.filter((log) => {
        if (selectedAdminId !== "all") {
          const performerId = String(
            log?.performedBy?.uid || log.performedById || log.performedByUid || "",
          ).trim();
          if (performerId !== selectedAdminId) return false;
        }
        if (dateFilter) {
          const dt = log.timestamp?.toDate?.();
          if (!dt) return false;
          const day = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
          if (day !== dateFilter) return false;
        }
        return true;
      }),
    [logs, selectedAdminId, dateFilter],
  );

  const metrics = useMemo(() => {
    const countByAction = (type) => filteredLogs.filter((log) => log.actionType === type).length;
    const totalActions = filteredLogs.length;
    const driversApproved = countByAction("Driver Approved");
    const driversRejected = countByAction("Driver Rejected");
    const reviewsRemoved = countByAction("Review Removed");
    const routesAdded = countByAction("Route Added");
    const routesDeleted = countByAction("Route Deleted");
    const parentsManaged = filteredLogs.filter((log) =>
      ["Parent Deleted", "Parent Restored"].includes(log.actionType),
    ).length;

    const deletedDrivers = countByAction("Driver Deleted");
    const deletedReviews = reviewsRemoved;
    const deletedParents = countByAction("Parent Deleted");
    const deletedRoutes = routesDeleted;

    return {
      totalActions,
      driversApproved,
      driversRejected,
      reviewsRemoved,
      routesAdded,
      routesDeleted,
      parentsManaged,
      deletedDrivers,
      deletedReviews,
      deletedParents,
      deletedRoutes,
    };
  }, [filteredLogs]);

  return (
    <div className="space-y-6">
      <div>
        <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-fuchsia-600 bg-clip-text text-transparent">
          Admin Reports
        </h2>
        <p className="text-gray-600 mt-1">Admin performance and accountability reports</p>
      </div>

      <div className="bg-white rounded-2xl border border-gray-100 shadow p-4">
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <select
            value={selectedAdminId}
            onChange={(e) => setSelectedAdminId(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
          >
            <option value="all">All admins</option>
            {admins.map((admin) => (
              <option key={admin.id} value={admin.id}>
                {admin.name || admin.email || "Admin"}
              </option>
            ))}
          </select>
          <input
            type="date"
            value={dateFilter}
            onChange={(e) => setDateFilter(e.target.value)}
            className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
          />
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <div className="rounded-2xl p-5 text-white shadow bg-gradient-to-r from-violet-500 to-purple-600">
          <p className="text-sm text-white/90">Total Actions Performed</p>
          <p className="text-3xl font-bold mt-2">{metrics.totalActions}</p>
        </div>
        <div className="rounded-2xl p-5 text-white shadow bg-gradient-to-r from-emerald-500 to-teal-600">
          <p className="text-sm text-white/90">Drivers Approved</p>
          <p className="text-3xl font-bold mt-2">{metrics.driversApproved}</p>
        </div>
        <div className="rounded-2xl p-5 text-white shadow bg-gradient-to-r from-amber-500 to-orange-600">
          <p className="text-sm text-white/90">Drivers Rejected</p>
          <p className="text-3xl font-bold mt-2">{metrics.driversRejected}</p>
        </div>
        <div className="rounded-2xl p-5 text-white shadow bg-gradient-to-r from-cyan-500 to-blue-600">
          <p className="text-sm text-white/90">Reviews Removed</p>
          <p className="text-3xl font-bold mt-2">{metrics.reviewsRemoved}</p>
        </div>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        <div className="bg-white rounded-2xl border border-gray-100 shadow p-5">
          <h3 className="text-lg font-semibold text-gray-800 mb-3">Route & Parent Activity</h3>
          <p className="text-sm text-gray-700">Routes Added: {metrics.routesAdded}</p>
          <p className="text-sm text-gray-700">Routes Deleted: {metrics.routesDeleted}</p>
          <p className="text-sm text-gray-700">Parents Managed: {metrics.parentsManaged}</p>
        </div>

        <div className="bg-white rounded-2xl border border-gray-100 shadow p-5">
          <h3 className="text-lg font-semibold text-gray-800 mb-3">Deletion Statistics</h3>
          <p className="text-sm text-gray-700">Drivers Deleted: {metrics.deletedDrivers}</p>
          <p className="text-sm text-gray-700">Reviews Removed: {metrics.deletedReviews}</p>
          <p className="text-sm text-gray-700">Parents Deleted: {metrics.deletedParents}</p>
          <p className="text-sm text-gray-700">Routes Deleted: {metrics.deletedRoutes}</p>
        </div>
      </div>

      <div className="bg-white rounded-2xl border border-gray-100 shadow p-5">
        <h3 className="text-lg font-semibold text-gray-800 mb-3">Admin Profile</h3>
        {selectedAdmin ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-y-2 gap-x-4 text-sm text-gray-700">
            <p><span className="font-semibold text-gray-800">Name:</span> {selectedAdmin.name || "Not provided"}</p>
            <p><span className="font-semibold text-gray-800">Email:</span> {selectedAdmin.email || "Not provided"}</p>
            <p><span className="font-semibold text-gray-800">City:</span> {selectedAdmin.city || "Not provided"}</p>
            <p><span className="font-semibold text-gray-800">Role:</span> {selectedAdmin.role || "Not provided"}</p>
            <p><span className="font-semibold text-gray-800">Created At:</span> {formatCreatedAt(selectedAdmin.createdAt)}</p>
            <p><span className="font-semibold text-gray-800">Last Login:</span> {selectedAdmin.lastLoginAt ? formatDate(selectedAdmin.lastLoginAt) : "Not provided"}</p>
          </div>
        ) : (
          <p className="text-sm text-gray-600">Select an admin to view profile details.</p>
        )}
      </div>

      <div className="bg-white rounded-2xl border border-gray-100 shadow p-5">
        <h3 className="text-lg font-semibold text-gray-800 mb-3">Activity Timeline</h3>
        {filteredLogs.length === 0 ? (
          <p className="text-sm text-gray-500">No activity found for selected filters.</p>
        ) : (
          <div className="space-y-3">
            {filteredLogs.slice(0, 100).map((log) => (
              <div
                key={log.id}
                className="rounded-xl border border-gray-200 bg-gray-50 p-3"
              >
                <p className="text-sm font-semibold text-gray-800">{log.actionType || "Action"}</p>
                <p className="text-sm text-gray-700">Target: {toTargetLabel(log)}</p>
                <p className="text-xs text-gray-500 mt-1">{formatDate(log.timestamp)}</p>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
};

export default AdminReportsTab;
