import { addDoc, collection, deleteField, doc, getDoc, serverTimestamp, updateDoc } from "firebase/firestore";
import { db } from "../firebase";

export const buildAuditActor = (profile, user) => {
  const email = String(profile?.email || user?.email || "").trim();
  const explicitName = String(
    profile?.name || profile?.fullName || profile?.displayName || user?.displayName || "",
  ).trim();
  const emailName = email.includes("@") ? email.split("@")[0] : "";
  const role = String(profile?.role || "admin").trim() || "admin";
  return {
    uid: String(user?.uid || "").trim(),
    name: explicitName || emailName || "Not provided",
    role,
    email: email || "Not provided",
  };
};

export const writeAuditLog = async ({
  actionType,
  performedBy = null,
  performedByName = "",
  performedById = "",
  performedByUid = "",
  target = null,
  targetType = "",
  targetId = "",
  targetName = "",
  reviewId = "",
  reviewSnapshot = null,
  routeName = "",
  details = "",
  entityName = "",
  driverName = "",
  parentName = "",
  reviewText = "",
  rating = null,
  metadata = null,
}) => {
  try {
    const actorObj = performedBy && typeof performedBy === "object" ? performedBy : null;
    const normalizedPerformedById = String(
      actorObj?.uid || performedById || performedByUid || "",
    ).trim();
    let normalizedPerformedByName = String(
      actorObj?.name || performedByName || "",
    ).trim();
    const normalizedRole = String(actorObj?.role || "admin").trim() || "admin";
    let normalizedEmail = String(actorObj?.email || "").trim();

    if (!normalizedPerformedByName && normalizedPerformedById) {
      try {
        const userSnap = await getDoc(doc(db, "users", normalizedPerformedById));
        if (userSnap.exists()) {
          const userData = userSnap.data();
          normalizedPerformedByName = String(
            userData.name || userData.fullName || userData.displayName || userData.email || "",
          ).trim();
          normalizedEmail = normalizedEmail || String(userData.email || "").trim();
        }
      } catch (_) {
        // Allow write to continue.
      }
    }

    if (!normalizedPerformedByName) normalizedPerformedByName = "Not provided";
    if (!normalizedEmail) normalizedEmail = "Not provided";

    const normalizedTargetType = String(target?.type || targetType || "").trim() || "record";
    const normalizedTargetId = String(target?.id || targetId || "").trim() || "not-provided";
    const normalizedRouteName =
      String(routeName || "").trim() ||
      (normalizedTargetType === "route" ? String(entityName || "").trim() : "");
    const normalizedTargetName = String(
      target?.name || targetName || entityName || normalizedRouteName || "",
    ).trim() || "Not provided";

    const normalizedMetadata =
      metadata && typeof metadata === "object" ? { ...metadata } : {};
    if (reviewSnapshot && typeof reviewSnapshot === "object") {
      normalizedMetadata.review = reviewSnapshot;
    }
    if (driverName) normalizedMetadata.driverName = String(driverName).trim();
    if (parentName) normalizedMetadata.parentName = String(parentName).trim();
    if (reviewText) normalizedMetadata.reviewText = String(reviewText).trim();
    if (typeof rating === "number" && Number.isFinite(rating)) {
      normalizedMetadata.rating = rating;
    }

    await addDoc(collection(db, "audit_logs"), {
      actionType,
      performedBy: {
        uid: normalizedPerformedById || "not-provided",
        name: normalizedPerformedByName,
        role: normalizedRole,
        email: normalizedEmail,
      },
      performedByName: `${normalizedPerformedByName} (${normalizedRole})`,
      ...(normalizedPerformedById ? { performedById: normalizedPerformedById } : {}),
      ...(normalizedPerformedById ? { performedByUid: normalizedPerformedById } : {}),
      target: {
        type: normalizedTargetType,
        id: normalizedTargetId,
        name: normalizedTargetName,
      },
      targetType: normalizedTargetType,
      targetId: normalizedTargetId,
      ...(reviewId ? { reviewId } : {}),
      ...(reviewSnapshot && typeof reviewSnapshot === "object" ? { reviewSnapshot } : {}),
      routeName: normalizedRouteName,
      driverName: String(driverName || "").trim(),
      parentName: String(parentName || "").trim(),
      reviewText: String(reviewText || "").trim(),
      rating: typeof rating === "number" && Number.isFinite(rating) ? rating : null,
      metadata: normalizedMetadata,
      details,
      ...(entityName ? { entityName } : {}),
      timestamp: serverTimestamp(),
    });
  } catch (err) {
    console.error("[audit_logs] failed to write log:", err);
  }
};

export const softDeleteDocument = async (collectionName, id, deletedBy, extraFields = {}) => {
  await updateDoc(doc(db, collectionName, id), {
    isDeleted: true,
    deletedAt: serverTimestamp(),
    deletedBy,
    ...extraFields,
  });
};

export const restoreSoftDeletedDocument = async (collectionName, id, restoreFields = {}) => {
  await updateDoc(doc(db, collectionName, id), {
    isDeleted: false,
    deletedAt: deleteField(),
    deletedBy: deleteField(),
    ...restoreFields,
  });
};
