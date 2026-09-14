import React, { useEffect, useMemo, useState } from "react";
import { collection, onSnapshot, query, where } from "firebase/firestore";
import { auth, db } from "../firebase";
import { buildAuditActor, restoreSoftDeletedDocument, writeAuditLog } from "../lib/auditRecovery";

const sectionConfig = [
  { key: "drivers", title: "Deleted Drivers", collectionName: "users", role: "driver" },
  { key: "parents", title: "Deleted Parents", collectionName: "users", role: "parent" },
  { key: "reviews", title: "Deleted Reviews", collectionName: "reviews" },
  { key: "routes", title: "Deleted Routes", collectionName: "routes" },
  { key: "schools", title: "Deleted Schools", collectionName: "schools" },
];

const formatDate = (value) => {
  const date = value?.toDate?.();
  return date ? date.toLocaleString() : "Not available";
};

const maskCnic = (cnicValue) => {
  const cnic = String(cnicValue || "").trim();
  if (!cnic) return "Not provided";
  const digits = cnic.replace(/\D/g, "");
  if (digits.length < 5) return "Masked";
  return `${digits.slice(0, 5)}-*******-*`;
};

const buildVehicleLabel = (driver) => {
  const parts = [
    driver.vehicleName,
    driver.vehicleModel,
    driver.vehicleNumber,
    driver.vehicleNo,
  ]
    .map((item) => String(item || "").trim())
    .filter(Boolean);
  return parts.length > 0 ? parts.join(" • ") : "Not provided";
};

const buildSchoolLocation = (school) => {
  if (school.address) return String(school.address);
  if (school.locationName) return String(school.locationName);
  if (
    typeof school.latitude === "number" &&
    typeof school.longitude === "number"
  ) {
    return `${school.latitude.toFixed(4)}, ${school.longitude.toFixed(4)}`;
  }
  return "Not provided";
};

const buildDeletedByLabel = (item, usersById) => {
  const user = usersById[item.deletedBy];
  if (user?.name) return user.name;
  if (user?.email) return user.email;
  return "Admin";
};

const resolveDriverNameFromRoute = (route, usersById) => {
  if (route.driverName) return String(route.driverName);
  const linkedDriverId =
    route.driverId || route.assignedDriver || route.driverUid || "";
  const linkedDriver = usersById[linkedDriverId];
  if (linkedDriver?.name) return linkedDriver.name;
  if (linkedDriver?.email) return linkedDriver.email;
  return "Not assigned";
};

const resolveUserName = (userId, usersById, fallbackLabel) => {
  const user = usersById[userId];
  if (user?.name) return user.name;
  if (user?.email) return user.email;
  return fallbackLabel;
};

const DetailsRow = ({ label, value }) => (
  <div className="grid grid-cols-[120px_1fr] gap-2 text-sm">
    <span className="text-slate-500">{label}</span>
    <span className="font-medium text-slate-800 break-words">{value}</span>
  </div>
);

const DeletedRecordsTab = ({ adminProfile, showHeader = true }) => {
  const [deletedData, setDeletedData] = useState({
    drivers: [],
    parents: [],
    reviews: [],
    routes: [],
    schools: [],
  });
  const [usersById, setUsersById] = useState({});
  const [restoringId, setRestoringId] = useState("");

  useEffect(() => {
    const unsubscribers = sectionConfig.map((section) => {
      const constraints = [where("isDeleted", "==", true)];
      if (section.role) constraints.push(where("role", "==", section.role));
      const q = query(collection(db, section.collectionName), ...constraints);
      return onSnapshot(q, (snapshot) => {
        const mapped = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }));
        setDeletedData((prev) => ({ ...prev, [section.key]: mapped }));
      });
    });

    return () => unsubscribers.forEach((unsub) => unsub());
  }, []);

  useEffect(() => {
    const unsubUsers = onSnapshot(collection(db, "users"), (snapshot) => {
      const nextLookup = {};
      snapshot.docs.forEach((d) => {
        nextLookup[d.id] = { id: d.id, ...d.data() };
      });
      setUsersById(nextLookup);
    });
    return () => unsubUsers();
  }, []);

  const totalDeleted = useMemo(
    () => Object.values(deletedData).reduce((sum, arr) => sum + arr.length, 0),
    [deletedData],
  );

  const restoreRecord = async (section, item) => {
    const restoringKey = `${section.key}:${item.id}`;
    setRestoringId(restoringKey);
    try {
      const restoreFields =
        section.key === "reviews"
          ? { status: "active" }
          : {};
      await restoreSoftDeletedDocument(section.collectionName, item.id, restoreFields);
      const actionTypeBySection = {
        drivers: "Driver Restored",
        parents: "Parent Restored",
        reviews: "Review Restored",
        routes: "Route Restored",
        schools: "School Restored",
      };
      await writeAuditLog({
        actionType: actionTypeBySection[section.key] || "Record Restored",
        performedBy: buildAuditActor(adminProfile, auth.currentUser),
        performedByName: String(adminProfile?.name || auth.currentUser?.displayName || "").trim(),
        performedByUid: auth.currentUser?.uid || "",
        targetType: section.key.slice(0, -1),
        targetId: item.id,
        reviewId: section.key === "reviews" ? String(item.auditSnapshot?.reviewId || item.id) : "",
        reviewSnapshot:
          section.key === "reviews"
            ? {
              reviewId: String(item.auditSnapshot?.reviewId || item.id),
              driverName: String(
                item.auditSnapshot?.driverName ||
                resolveUserName(item.driverId, usersById, "") ||
                item.driverName ||
                "Driver record",
              ),
              parentName: String(
                item.auditSnapshot?.parentName ||
                resolveUserName(item.parentId, usersById, "") ||
                item.parentName ||
                "Parent record",
              ),
              comment: String(item.auditSnapshot?.comment ?? item.comment ?? "").trim() || "No comment",
              rating: Number.isFinite(Number(item.auditSnapshot?.rating))
                ? Number(item.auditSnapshot?.rating)
                : Number.isFinite(Number(item.rating))
                  ? Number(item.rating)
                  : null,
            }
            : null,
        entityName:
          section.key === "schools" || section.key === "routes"
            ? String(item.name || "")
            : String(item.name || item.email || ""),
        routeName: section.key === "routes" ? String(item.name || "") : "",
        driverName:
          section.key === "reviews"
            ? String(
              item.auditSnapshot?.driverName ||
              resolveUserName(item.driverId, usersById, "") ||
              item.driverName ||
              "",
            )
            : "",
        parentName:
          section.key === "reviews"
            ? String(
              item.auditSnapshot?.parentName ||
              resolveUserName(item.parentId, usersById, "") ||
              item.parentName ||
              "",
            )
            : "",
        reviewText:
          section.key === "reviews"
            ? String(item.auditSnapshot?.comment ?? item.comment ?? "").trim()
            : "",
        rating:
          section.key === "reviews"
            ? Number.isFinite(Number(item.auditSnapshot?.rating))
              ? Number(item.auditSnapshot?.rating)
              : Number.isFinite(Number(item.rating))
                ? Number(item.rating)
                : null
            : null,
        details: `${section.title.replace("Deleted ", "").replace(/s$/, "")} was restored successfully.`,
      });
    } finally {
      setRestoringId("");
    }
  };

  const renderReadableFields = (sectionKey, item) => {
    const deletedByLabel = buildDeletedByLabel(item, usersById);
    const deletedAtLabel = formatDate(item.deletedAt);

    if (sectionKey === "drivers") {
      return (
        <>
          <DetailsRow label="Name" value={String(item.name || item.email || "Driver")} />
          <DetailsRow label="CNIC" value={maskCnic(item.cnic)} />
          <DetailsRow label="Vehicle" value={buildVehicleLabel(item)} />
          <DetailsRow label="Deleted By" value={deletedByLabel} />
          <DetailsRow label="Date" value={deletedAtLabel} />
        </>
      );
    }

    if (sectionKey === "parents") {
      const childrenCount = Array.isArray(item.children) ? item.children.length : 0;
      return (
        <>
          <DetailsRow label="Name" value={String(item.name || item.email || "Parent")} />
          <DetailsRow label="Children" value={`${childrenCount}`} />
          <DetailsRow label="City" value={String(item.city || "Not provided")} />
          <DetailsRow label="Deleted By" value={deletedByLabel} />
          <DetailsRow label="Date" value={deletedAtLabel} />
        </>
      );
    }

    if (sectionKey === "reviews") {
      const driverName = resolveUserName(item.driverId, usersById, "Unknown Driver");
      const parentName = resolveUserName(item.parentId, usersById, "Unknown Parent");
      return (
        <>
          <DetailsRow label="Driver" value={driverName} />
          <DetailsRow label="Parent" value={parentName} />
          <DetailsRow label="Rating" value={`${Number(item.rating || 0).toFixed(1)} / 5`} />
          <DetailsRow label="Comment" value={String(item.comment || "No comment")} />
          <DetailsRow label="Deleted By" value={deletedByLabel} />
          <DetailsRow label="Date" value={deletedAtLabel} />
        </>
      );
    }

    if (sectionKey === "routes") {
      return (
        <>
          <DetailsRow label="Route" value={String(item.name || "Unnamed route")} />
          <DetailsRow label="Driver" value={resolveDriverNameFromRoute(item, usersById)} />
          <DetailsRow label="Deleted By" value={deletedByLabel} />
          <DetailsRow label="Date" value={deletedAtLabel} />
        </>
      );
    }

    return (
      <>
        <DetailsRow label="School" value={String(item.name || "Unnamed school")} />
        <DetailsRow label="Location" value={buildSchoolLocation(item)} />
        <DetailsRow label="Deleted By" value={deletedByLabel} />
        <DetailsRow label="Date" value={deletedAtLabel} />
      </>
    );
  };

  return (
    <div className="space-y-6">
      {showHeader ? (
        <div>
          <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
            Deleted Records
          </h1>
          <p className="text-slate-600 mt-1">Soft-deleted data and quick recovery actions</p>
        </div>
      ) : null}

      <div className="bg-white rounded-2xl p-5 shadow-lg border border-slate-100">
        <p className="text-sm text-slate-600">
          Total soft-deleted records: <span className="font-semibold text-slate-800">{totalDeleted}</span>
        </p>
      </div>

      <div className="grid grid-cols-1 xl:grid-cols-2 gap-6">
        {sectionConfig.map((section) => {
          const items = deletedData[section.key] || [];
          return (
            <div key={section.key} className="bg-white rounded-2xl p-5 shadow-lg border border-slate-100">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-slate-800">{section.title}</h3>
                <span className="text-xs px-2.5 py-1 rounded-full bg-slate-100 text-slate-700">
                  {items.length}
                </span>
              </div>

              {items.length === 0 ? (
                <p className="text-sm text-slate-500">No deleted records in this section.</p>
              ) : (
                <div className="space-y-3">
                  {items.map((item) => {
                    const key = `${section.key}:${item.id}`;
                    const isRestoring = restoringId === key;
                    return (
                      <div
                        key={item.id}
                        className="border border-slate-200 rounded-xl p-4 bg-slate-50/70 flex flex-col sm:flex-row sm:items-start sm:justify-between gap-4"
                      >
                        <div className="min-w-0 flex-1 space-y-2">
                          <div className="flex items-center gap-2">
                            <span className="inline-flex px-2.5 py-1 rounded-full text-xs font-semibold bg-rose-100 text-rose-700">
                              Deleted
                            </span>
                            <span className="text-xs text-slate-500">{section.title.slice(8, -1)}</span>
                          </div>
                          {renderReadableFields(section.key, item)}
                        </div>
                        <button
                          onClick={() => restoreRecord(section, item)}
                          disabled={isRestoring}
                          className="px-3 py-2 rounded-lg text-sm font-medium bg-emerald-100 text-emerald-700 hover:bg-emerald-200 disabled:opacity-60 shrink-0"
                        >
                          {isRestoring ? "Restoring..." : "Restore"}
                        </button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
};

export default DeletedRecordsTab;
