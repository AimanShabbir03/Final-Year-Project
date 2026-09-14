import React, { useEffect, useRef, useState } from "react";
import { db, auth, storage } from "../firebase";
import {
  collection,
  query,
  where,
  onSnapshot,
  getDocs,
  updateDoc,
  doc,
  addDoc,
  getDoc,
  setDoc,
  serverTimestamp,
} from "firebase/firestore";
import { getDownloadURL, ref as storageRef, uploadBytesResumable } from "firebase/storage";
import { signOut } from "firebase/auth";
import DeleteConfirmModal from "../components/DeleteConfirmModal";
import AddSchoolMapModal from "../components/AddSchoolMapModal";
import AddRouteModal from "../components/AddRouteModal";
import ReportsTab from "../components/ReportsTab";
import LogsTab from "../components/LogsTab";
import DeletedRecordsTab from "../components/DeletedRecordsTab";
import { useToast } from "../contexts/ToastContext";
import { buildAuditActor, softDeleteDocument, writeAuditLog } from "../lib/auditRecovery";

const AdminDashboard = () => {
  const { success, error } = useToast();
  const [activeTab, setActiveTab] = useState("dashboard");
  const [collapsed, setCollapsed] = useState(false);
  const [deleteModal, setDeleteModal] = useState({ open: false, type: null, id: null, name: null });
  const [deleting, setDeleting] = useState(false);

  const [drivers, setDrivers] = useState([]);
  const [parents, setParents] = useState([]);
  const [routes, setRoutes] = useState([]);
  const [schools, setSchools] = useState([]);

  const [selectedDriver, setSelectedDriver] = useState(null);
  const [selectedParent, setSelectedParent] = useState(null);
  const [parentChildren, setParentChildren] = useState([]);

  const [adminProfile, setAdminProfile] = useState({
    name: "",
    phone: "",
    cnic: "",
    city: "Abbottabad",
  });

  const [allDriverRequests, setAllDriverRequests] = useState([]);
  const [reviews, setReviews] = useState([]);
  const [reviewsLoading, setReviewsLoading] = useState(true);
  const [reviewFilter, setReviewFilter] = useState("all");
  const [expandedReviewIds, setExpandedReviewIds] = useState({});
  const [reviewActionLoadingId, setReviewActionLoadingId] = useState(null);
  const [payments, setPayments] = useState([]);
  const [ledgerEntries, setLedgerEntries] = useState([]);
  const [ridesForPayments, setRidesForPayments] = useState([]);
  const [adminSalaryRecord, setAdminSalaryRecord] = useState(null);
  const [paymentHistoryFilters, setPaymentHistoryFilters] = useState({
    parentName: "",
    driverName: "",
    transactionId: "",
    status: "all",
    date: "",
  });
  const [paymentsLoading, setPaymentsLoading] = useState(true);
  const [ledgerLoading, setLedgerLoading] = useState(true);
  const [markingPaidId, setMarkingPaidId] = useState(null);
  const [savingProfile, setSavingProfile] = useState(false);
  const [uploadingProfileImage, setUploadingProfileImage] = useState(false);
  const [isProfilePhotoModalOpen, setIsProfilePhotoModalOpen] = useState(false);
  const [profileImagePreview, setProfileImagePreview] = useState(null);
  const [selectedProfileImageFile, setSelectedProfileImageFile] = useState(null);
  const [addingRoute, setAddingRoute] = useState(false);
  const [addingSchool, setAddingSchool] = useState(false);
  const [addSchoolMapOpen, setAddSchoolMapOpen] = useState(false);
  const [addRouteModalOpen, setAddRouteModalOpen] = useState(false);
  const profileImageInputRef = useRef(null);
  const profileUploadTaskRef = useRef(null);

  // Live driver location for map
  const [selectedDriverLocation, setSelectedDriverLocation] = useState(null);
  const mapRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const markerRef = useRef(null);

  // Collapse sidebar by default on mobile & tablet
  useEffect(() => {
    if (window.innerWidth < 1024) {
      setCollapsed(true);
    }
  }, []);

  // Subscribe to live location for selected driver
  useEffect(() => {
    if (!selectedDriver) {
      mapInstanceRef.current = null;
      markerRef.current = null;
      return;
    }

    mapInstanceRef.current = null;
    markerRef.current = null;

    const locRef = doc(db, "driverLocations", selectedDriver.id);
    const unsub = onSnapshot(locRef, (snap) => {
      if (!snap.exists()) {
        setSelectedDriverLocation(null);
        return;
      }
      const data = snap.data();
      if (typeof data.latitude === "number" && typeof data.longitude === "number") {
        setSelectedDriverLocation({
          lat: data.latitude,
          lng: data.longitude,
          updatedAt: data.timestamp,
        });
      } else {
        setSelectedDriverLocation(null);
      }
    });

    return () => unsub();
  }, [selectedDriver]);

  // Initialize/update Google Map when location changes
  useEffect(() => {
    if (!selectedDriverLocation || !window.google || !mapRef.current) return;

    const { lat, lng } = selectedDriverLocation;
    const position = { lat, lng };

    if (!mapInstanceRef.current) {
      mapInstanceRef.current = new window.google.maps.Map(mapRef.current, {
        center: position,
        zoom: 16,
        disableDefaultUI: false,
      });
      markerRef.current = new window.google.maps.Marker({
        position,
        map: mapInstanceRef.current,
        title: selectedDriver?.name || "Driver",
      });
    } else {
      markerRef.current.setPosition(position);
      mapInstanceRef.current.panTo(position);
    }
  }, [selectedDriverLocation, selectedDriver]);

  // Fetch admin profile
  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (user) {
        const adminRef = doc(db, "users", user.uid);
        const snap = await getDoc(adminRef);
        if (snap.exists()) setAdminProfile(snap.data());
      }
    });
    return () => unsubscribe();
  }, []);

  const saveAdminProfile = async () => {
    const user = auth.currentUser;
    if (!user) return;
    if (uploadingProfileImage) {
      error("Please wait for the image upload to finish or cancel it first.");
      return;
    }
    const phone = adminProfile.phone || "";
    // Expect Pakistani mobile like +92 3XX XXXXXXX
    if (!/^\+923\d{9}$/.test(phone)) {
      error("Please enter a valid Pakistani mobile number (e.g. +92 3XX XXXXXXX).");
      return;
    }
    setSavingProfile(true);
    try {
      const adminRef = doc(db, "users", user.uid);
      // Use setDoc with merge so the profile can be created if it doesn't exist yet
      await setDoc(adminRef, adminProfile, { merge: true });
      success("Profile saved!");
      setActiveTab("dashboard");
    } catch (e) {
      error("Failed to save profile.");
    } finally {
      setSavingProfile(false);
    }
  };

  useEffect(() => {
    return () => {
      if (profileUploadTaskRef.current) {
        try {
          profileUploadTaskRef.current.cancel();
        } catch (_) {
          // Ignore cleanup cancellation errors.
        }
      }
      if (profileImagePreview) {
        URL.revokeObjectURL(profileImagePreview);
      }
    };
  }, [profileImagePreview]);

  const onProfileImageFileChange = (event) => {
    const file = event.target.files?.[0];
    if (!file) return;

    const validTypes = ["image/jpeg", "image/jpg", "image/png"];
    if (!validTypes.includes(file.type)) {
      error("Only JPG and PNG image files are allowed.");
      event.target.value = "";
      return;
    }

    const maxSizeBytes = 2 * 1024 * 1024;
    if (file.size > maxSizeBytes) {
      error("Image size must be 2MB or less.");
      event.target.value = "";
      return;
    }

    if (profileImagePreview) {
      URL.revokeObjectURL(profileImagePreview);
    }
    const previewUrl = URL.createObjectURL(file);
    setProfileImagePreview(previewUrl);
    setSelectedProfileImageFile(file);
  };

  const clearProfileImageSelection = () => {
    if (profileImagePreview) {
      URL.revokeObjectURL(profileImagePreview);
    }
    setProfileImagePreview(null);
    setSelectedProfileImageFile(null);
    if (profileImageInputRef.current) {
      profileImageInputRef.current.value = "";
    }
  };

  const cancelProfileImageSelection = () => {
    if (profileUploadTaskRef.current) {
      try {
        profileUploadTaskRef.current.cancel();
      } catch (_) {
        // Ignore if task already ended.
      } finally {
        profileUploadTaskRef.current = null;
      }
    }
    setUploadingProfileImage(false);
    clearProfileImageSelection();
  };

  const uploadAdminProfileImage = (file, uid) => {
    if (!file) throw new Error("No file selected");
    if (!uid) throw new Error("User is not authenticated");

    const fileRef = storageRef(storage, `profile_photos/admin/${uid}.jpg`);
    const uploadTask = uploadBytesResumable(fileRef, file, {
      contentType: file.type || "image/jpeg",
    });

    const uploadPromise = new Promise((resolve, reject) => {
      uploadTask.on(
        "state_changed",
        () => {
          // Progress can be handled here later if needed.
        },
        (uploadError) => {
          console.log("UPLOAD ERROR:", uploadError);
          reject(uploadError);
        },
        async () => {
          try {
            const downloadURL = await getDownloadURL(uploadTask.snapshot.ref);
            resolve(downloadURL);
          } catch (urlError) {
            reject(urlError);
          }
        },
      );
    });

    return { uploadTask, uploadPromise };
  };

  const uploadProfileImage = async () => {
    if (uploadingProfileImage) return;
    const user = auth.currentUser;
    setUploadingProfileImage(true);
    try {
      if (!selectedProfileImageFile) {
        throw new Error("No file selected");
      }
      if (!user?.uid) {
        throw new Error("User is not authenticated");
      }

      const { uploadTask, uploadPromise } = uploadAdminProfileImage(
        selectedProfileImageFile,
        user.uid,
      );
      profileUploadTaskRef.current = uploadTask;
      const downloadUrl = await uploadPromise;
      await setDoc(
        doc(db, "users", user.uid),
        { profileImageUrl: downloadUrl },
        { merge: true },
      );
      setAdminProfile((prev) => ({ ...prev, profileImageUrl: downloadUrl }));
      success("Profile photo updated.");
      clearProfileImageSelection();
    } catch (e) {
      if (e?.code !== "storage/canceled") {
        error("Failed to upload profile photo.");
        clearProfileImageSelection();
      }
    } finally {
      profileUploadTaskRef.current = null;
      setUploadingProfileImage(false);
    }
  };

  useEffect(() => {
    const q = query(collection(db, "users"), where("role", "==", "driver"));
    const unsub = onSnapshot(q, (snapshot) => {
      setDrivers(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })).filter((d) => d.isDeleted !== true));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const q = query(collection(db, "users"), where("role", "==", "parent"));
    const unsub = onSnapshot(q, (snapshot) => {
      setParents(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })).filter((d) => d.isDeleted !== true));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "routes"), (snapshot) => {
      setRoutes(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })).filter((d) => d.isDeleted !== true));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "schools"), (snapshot) => {
      setSchools(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })).filter((d) => d.isDeleted !== true));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "requests"), (snapshot) => {
      setAllDriverRequests(
        snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() })),
      );
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(
      collection(db, "reviews"),
      (snapshot) => {
        setReviews(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })).filter((d) => d.isDeleted !== true));
        setReviewsLoading(false);
      },
      () => {
        setReviewsLoading(false);
      },
    );
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "payments"), (snapshot) => {
      setPayments(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
      setPaymentsLoading(false);
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "rides"), (snapshot) => {
      setRidesForPayments(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    const unsub = onSnapshot(collection(db, "earnings_ledger"), (snapshot) => {
      setLedgerEntries(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
      setLedgerLoading(false);
    });
    return () => unsub();
  }, []);

  useEffect(() => {
    if (!auth.currentUser?.uid) {
      setAdminSalaryRecord(null);
      return;
    }
    const currentMonthKey = "2026-06";
    const normalizedUid = String(auth.currentUser.uid || "").trim();
    console.log("[AdminSalaryDebug] currentUser.uid:", normalizedUid);
    const salaryQuery = query(
      collection(db, "admin_salaries"),
      where("adminId", "==", normalizedUid),
      where("monthKey", "==", currentMonthKey),
    );
    const unsub = onSnapshot(salaryQuery, (snapshot) => {
      const exactMatch = snapshot.docs.find((d) => {
        const data = d.data();
        return (
          String(data.adminId || "").trim() === normalizedUid &&
          String(data.monthKey || "").trim() === currentMonthKey.trim()
        );
      });

      if (exactMatch) {
        console.log(
          "[AdminSalaryDebug] matched Firestore adminId:",
          String(exactMatch.data().adminId || "").trim(),
        );
        setAdminSalaryRecord({ id: exactMatch.id, ...exactMatch.data() });
        return;
      }

      setAdminSalaryRecord(null);
      console.log("[AdminSalaryDebug] No matching salary record found for", {
        adminId: normalizedUid,
        monthKey: currentMonthKey,
      });
    });
    return () => unsub();
  }, [auth.currentUser?.uid]);

  const getPerformedBy = () => buildAuditActor(adminProfile, auth.currentUser);
  const getPerformedByName = () =>
    String(adminProfile?.name || auth.currentUser?.displayName || "").trim();
  const getPerformedByUid = () => auth.currentUser?.uid || "";
  const getDeletedBy = () => auth.currentUser?.uid || "unknown-admin";

  const markPaymentPaid = async (paymentDoc) => {
    if (!paymentDoc?.id || paymentDoc.status === "paid") return;
    setMarkingPaidId(paymentDoc.id);
    try {
      const paymentRef = doc(db, "payments", paymentDoc.id);
      await updateDoc(paymentRef, {
        status: "paid",
        paidAt: new Date(),
      });

      const rideId = paymentDoc.rideId;
      if (!rideId) {
        success("Payment marked paid.");
        return;
      }

      const rideRef = doc(db, "rides", rideId);
      const rideSnap = await getDoc(rideRef);
      if (!rideSnap.exists()) {
        success("Payment marked paid.");
        return;
      }

      const rideData = rideSnap.data();
      await updateDoc(rideRef, { paymentStatus: "paid" });

      const existingLedgerQuery = query(
        collection(db, "earnings_ledger"),
        where("paymentId", "==", paymentDoc.id),
      );
      const existingLedgerSnap = await getDocs(existingLedgerQuery);
      if (existingLedgerSnap.empty) {
        const fare = Number(rideData.fare || paymentDoc.amount || 0);
        await addDoc(collection(db, "earnings_ledger"), {
          rideId,
          paymentId: paymentDoc.id,
          driverId: rideData.driverId || "",
          driverAmount: Number((fare * 0.7).toFixed(2)),
          superAdminAmount: Number((fare * 0.3).toFixed(2)),
          split: "70_30",
          createdAt: new Date(),
        });
      }

      success("Payment marked paid and earnings updated.");
      await writeAuditLog({
        actionType: "Payment Status Updated",
        performedBy: getPerformedBy(),
        performedByName: getPerformedByName(),
        performedByUid: getPerformedByUid(),
        targetType: "payment",
        targetId: paymentDoc.id,
        parentName: paymentDoc.parentName || "Parent",
        details: "Payment was marked as paid.",
      });
    } catch (e) {
      error("Failed to mark payment paid.");
    } finally {
      setMarkingPaidId(null);
    }
  };

  const approveDriver = async (id) => {
    const driverRef = doc(db, "users", id);
    const driverSnap = await getDoc(driverRef);
    const driverData = driverSnap.data();
    if (!driverData.route || !driverData.school) {
      error("Assign route and school before approving.");
      return;
    }
    try {
      await updateDoc(driverRef, {
        status: "active",
        isApproved: true,
        assignedSeats: 0,
        availableSeats: driverData.seats || 0,
      });
      await writeAuditLog({
        actionType: "Driver Approved",
        performedBy: getPerformedBy(),
        performedByName: getPerformedByName(),
        performedByUid: getPerformedByUid(),
        targetType: "driver",
        targetId: id,
        entityName: driverData.name || driverData.email || "Driver",
        details: `${driverData.name || "Driver"} was approved for active service.`,
      });
      success("Driver approved.");
    } catch (e) {
      error("Failed to approve driver.");
    }
  };

  const rejectDriver = async (id) => {
    try {
      const driverRef = doc(db, "users", id);
      const driverSnap = await getDoc(driverRef);
      const driverData = driverSnap.exists() ? driverSnap.data() : {};
      await updateDoc(driverRef, {
        status: "inactive",
        isApproved: false,
      });
      await writeAuditLog({
        actionType: "Driver Rejected",
        performedBy: getPerformedBy(),
        performedByName: getPerformedByName(),
        performedByUid: getPerformedByUid(),
        targetType: "driver",
        targetId: id,
        entityName: driverData.name || driverData.email || "Driver",
        details: `${driverData.name || "Driver"} registration was rejected.`,
      });
      success("Driver rejected.");
    } catch (e) {
      error("Failed to reject driver.");
    }
  };

  const openDeleteModal = (type, id, name) => {
    setDeleteModal({ open: true, type, id, name });
  };

  const handleConfirmDelete = async () => {
    if (!deleteModal.id || !deleteModal.type) return;
    setDeleting(true);
    try {
      let actionType = "";
      let targetType = "";
      if (deleteModal.type === "driver" || deleteModal.type === "parent") {
        const userRef = doc(db, "users", deleteModal.id);
        const userSnap = await getDoc(doc(db, "users", deleteModal.id));
        const userData = userSnap.exists() ? userSnap.data() : {};
        if (deleteModal.type === "driver") {
          await updateDoc(userRef, {
            status: "inactive",
            isApproved: false,
          });
        }
        await softDeleteDocument("users", deleteModal.id, getDeletedBy());
        actionType = deleteModal.type === "driver" ? "Driver Deleted" : "Parent Deleted";
        targetType = deleteModal.type;
        await writeAuditLog({
          actionType,
          performedBy: getPerformedBy(),
          performedByName: getPerformedByName(),
          performedByUid: getPerformedByUid(),
          targetType,
          targetId: deleteModal.id,
          entityName: userData.name || userData.email || deleteModal.name || "User",
          details:
            deleteModal.type === "driver"
              ? `${userData.name || "Driver"} was moved to deleted records.`
              : `${userData.name || "Parent"} was moved to deleted records.`,
        });
      } else if (deleteModal.type === "route") {
        const routeSnap = await getDoc(doc(db, "routes", deleteModal.id));
        const routeData = routeSnap.exists() ? routeSnap.data() : {};
        await softDeleteDocument("routes", deleteModal.id, getDeletedBy());
        actionType = "Route Deleted";
        targetType = "route";
        await writeAuditLog({
          actionType,
          performedBy: getPerformedBy(),
          performedByName: getPerformedByName(),
          performedByUid: getPerformedByUid(),
          targetType,
          targetId: deleteModal.id,
          entityName: routeData.name || deleteModal.name || "Route",
          routeName: routeData.name || deleteModal.name || "Route",
          driverName: routeData.driverName || "",
          details: `${routeData.name || "Route"} was moved to deleted records.`,
        });
      } else if (deleteModal.type === "school") {
        const schoolSnap = await getDoc(doc(db, "schools", deleteModal.id));
        const schoolData = schoolSnap.exists() ? schoolSnap.data() : {};
        await softDeleteDocument("schools", deleteModal.id, getDeletedBy());
        actionType = "School Deleted";
        targetType = "school";
        await writeAuditLog({
          actionType,
          performedBy: getPerformedBy(),
          performedByName: getPerformedByName(),
          performedByUid: getPerformedByUid(),
          targetType,
          targetId: deleteModal.id,
          entityName: schoolData.name || deleteModal.name || "School",
          details: `${schoolData.name || "School"} was moved to deleted records.`,
        });
      }
      success(
        deleteModal.type === "driver"
          ? "Driver removed."
          : deleteModal.type === "parent"
            ? "Parent removed."
            : deleteModal.type === "route"
              ? "Route deleted."
              : "School deleted."
      );
      setDeleteModal({ open: false, type: null, id: null, name: null });
    } catch (e) {
      error("Failed to delete. Please try again.");
    } finally {
      setDeleting(false);
    }
  };

  const removeDriver = (id, name) => {
    openDeleteModal("driver", id, name || "this driver");
  };

  const removeParent = (id, name) => {
    openDeleteModal("parent", id, name || "this parent");
  };

  const fetchChildren = (parent) => {
    const children = parent.children || [];
    setParentChildren(children.map((c, index) => ({ id: index, ...c })));
  };

  const addRouteFromModal = async (routeData) => {
    setAddingRoute(true);
    try {
      const fare = Number(routeData.fare);
      if (!Number.isFinite(fare) || fare <= 0) {
        error("Please provide a valid fare greater than 0.");
        return;
      }
      const name = `${routeData.schoolName} → ${routeData.destinationName}`;
      const createdRoute = await addDoc(collection(db, "routes"), {
        name,
        schoolName: routeData.schoolName,
        schoolLatitude: routeData.schoolLatitude,
        schoolLongitude: routeData.schoolLongitude,
        ...(routeData.schoolId && { schoolId: routeData.schoolId }),
        destinationName: routeData.destinationName,
        destinationLatitude: routeData.destinationLatitude,
        destinationLongitude: routeData.destinationLongitude,
        ...(routeData.destinationAddress && { destinationAddress: routeData.destinationAddress }),
        fare,
        createdAt: new Date(),
        updatedAt: new Date(),
      });
      await writeAuditLog({
        actionType: "Route Added",
        performedBy: getPerformedBy(),
        performedByName: getPerformedByName(),
        performedByUid: getPerformedByUid(),
        targetType: "route",
        targetId: createdRoute.id,
        entityName: name,
        routeName: name,
        details: `New route "${name}" was added.`,
      });
      success("Route added with school and destination.");
      setAddRouteModalOpen(false);
    } catch (e) {
      error("Failed to add route.");
    } finally {
      setAddingRoute(false);
    }
  };

  const deleteRoute = (id, name) => {
    openDeleteModal("route", id, name || "this route");
  };

  const updateRouteFare = async (routeId, fareValue) => {
    const parsedFare = Number(fareValue);
    if (!Number.isFinite(parsedFare) || parsedFare <= 0) {
      error("Fare must be a number greater than 0.");
      return;
    }
    try {
      await updateDoc(doc(db, "routes", routeId), {
        fare: parsedFare,
        updatedAt: new Date(),
      });
      success("Route fare updated.");
    } catch (e) {
      error("Failed to update route fare.");
    }
  };

  const addSchoolFromMap = async (school) => {
    setAddingSchool(true);
    try {
      const schoolRef = await addDoc(collection(db, "schools"), {
        name: school.name,
        latitude: school.latitude,
        longitude: school.longitude,
        ...(school.address && { address: school.address }),
      });
      await writeAuditLog({
        actionType: "School Added",
        performedBy: getPerformedBy(),
        performedByName: getPerformedByName(),
        performedByUid: getPerformedByUid(),
        targetType: "school",
        targetId: schoolRef.id,
        entityName: school.name || "School",
        details: `${school.name || "School"} was added to schools list.`,
      });
      success("School added with location.");
      setAddSchoolMapOpen(false);
    } catch (e) {
      error("Failed to add school.");
    } finally {
      setAddingSchool(false);
    }
  };

  const deleteSchool = (id, name) => {
    openDeleteModal("school", id, name || "this school");
  };

  const logout = async () => {
    await signOut(auth);
    window.location.href = "/";
  };

  const assignDriverToChild = async (parent, childIndex, driverId) => {
    const parentRef = doc(db, "users", parent.id);
    const driverRef = doc(db, "users", driverId);
    const updatedChildren = parent.children.map((c, index) =>
      index === childIndex ? { ...c, assignedDriver: driverId } : c,
    );
    await updateDoc(parentRef, { children: updatedChildren });
    const driverSnap = await getDoc(driverRef);
    const driverData = driverSnap.data();
    await updateDoc(driverRef, {
      assignedSeats: (driverData.assignedSeats || 0) + 1,
      availableSeats: (driverData.availableSeats ?? driverData.seats ?? 0) - 1,
    });
    await addDoc(collection(db, "requests"), {
      parentId: parent.id,
      parentName: parent.name || "Unknown Parent",
      driverId,
      childIds: [updatedChildren[childIndex].name],
      status: "approved",
      createdAt: new Date(),
    });
    success("Driver assigned. They will see this child in their app.");
    fetchChildren({ ...parent, children: updatedChildren });
  };

  const approveRequest = async (req) => {
    try {
      const parentRef = doc(db, "users", req.parentId);
      const parentSnap = await getDoc(parentRef);
      const parentData = parentSnap.data();
      const updatedChildren = (parentData.children || []).map((child) =>
        req.childIds?.includes(child.name)
          ? { ...child, assignedDriver: req.driverId }
          : child,
      );

      // Also update the driver's seat count
      const driverRef = doc(db, "users", req.driverId);
      const driverSnap = await getDoc(driverRef);
      const driverData = driverSnap.data();
      const numChildren = req.childIds?.length || 0;
      await updateDoc(driverRef, {
        assignedSeats: (driverData.assignedSeats || 0) + numChildren,
        availableSeats: (driverData.availableSeats ?? driverData.seats ?? 0) - numChildren,
      });

      await updateDoc(doc(db, "requests", req.id), { status: "approved" });
      await updateDoc(parentRef, { children: updatedChildren });
      success("Request approved.");
    } catch (e) {
      error("Failed to approve request.");
    }
  };

  const syncDriverSeats = async (driver) => {
    const assigned = parents.flatMap(p => (p.children || []).filter(c => c.assignedDriver === driver.id)).length;
    const total = parseInt(driver.seats) || 0;
    const available = total - assigned;

    try {
      await updateDoc(doc(db, "users", driver.id), {
        assignedSeats: assigned,
        availableSeats: available
      });
      await writeAuditLog({
        actionType: "Driver Availability Updated",
        performedBy: getPerformedBy(),
        performedByName: getPerformedByName(),
        performedByUid: getPerformedByUid(),
        targetType: "driver",
        targetId: driver.id,
        entityName: driver.name || driver.email || "Driver",
        details: `${driver.name || "Driver"} seats updated (${assigned} assigned, ${available} available).`,
      });
      success("Database synced with actual assignments!");
    } catch (e) {
      error("Failed to sync database.");
    }
  };

  const rejectRequest = async (reqId) => {
    try {
      await updateDoc(doc(db, "requests", reqId), { status: "rejected" });
      success("Request rejected.");
    } catch (e) {
      error("Failed to reject request.");
    }
  };

  const formatReviewDate = (createdAt) => {
    if (!createdAt?.toDate) return "—";
    return createdAt.toDate().toLocaleDateString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
    });
  };

  const normalizeStatus = (statusValue) => {
    const normalized = String(statusValue || "").toLowerCase().trim();
    if (
      normalized === "flagged" ||
      normalized === "resolved" ||
      normalized === "dismissed" ||
      normalized === "under_review" ||
      normalized === "deleted" ||
      normalized === "removed_by_admin" ||
      normalized === "active"
    ) {
      return normalized;
    }
    return "normal";
  };

  const toggleReviewExpanded = (reviewId) => {
    setExpandedReviewIds((prev) => ({ ...prev, [reviewId]: !prev[reviewId] }));
  };

  const updateReviewStatus = async (review, nextStatus) => {
    const statusMessageByType = {
      resolved:
        "Your review/complaint has been resolved by admin.",
      dismissed:
        "Your review/complaint has been dismissed by admin.",
      under_review:
        "Your review/complaint is under admin review.",
      removed_by_admin:
        "Your review/complaint has been removed by admin.",
    };

    const message = statusMessageByType[nextStatus];
    if (!message) return;

    setReviewActionLoadingId(review.id);
    try {
      if (nextStatus === "removed_by_admin") {
        const toText = (value) => String(value ?? "").trim();
        const firstNonEmptyText = (...values) => {
          for (const value of values) {
            const text = toText(value);
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

        const driverId = firstNonEmptyText(review.driverId, review.driverID, review.driverUid);
        const parentId = firstNonEmptyText(review.parentId, review.parentID, review.parentUid);
        const cachedDriverName = drivers.find((d) => d.id === driverId)?.name || "";
        const cachedParentName = parents.find((p) => p.id === parentId)?.name || "";

        const [driverSnap, parentSnap] = await Promise.all([
          driverId ? getDoc(doc(db, "users", driverId)) : Promise.resolve(null),
          parentId ? getDoc(doc(db, "users", parentId)) : Promise.resolve(null),
        ]);

        const driverData = driverSnap?.exists?.() ? driverSnap.data() : {};
        const parentData = parentSnap?.exists?.() ? parentSnap.data() : {};
        const driverNameSnapshot = firstNonEmptyText(
          review.driverName,
          cachedDriverName,
          driverData.name,
          driverData.email,
          "Driver record",
        );
        const parentNameSnapshot = firstNonEmptyText(
          review.parentName,
          cachedParentName,
          parentData.name,
          parentData.email,
          "Parent record",
        );
        const commentSnapshot = firstNonEmptyText(
          review.comment,
          review.reviewText,
          review.text,
          review.message,
          "No comment",
        );
        const ratingSnapshot = firstFiniteNumber(
          review.rating,
          review.stars,
          review.ratingValue,
        );
        const reviewIdSnapshot = firstNonEmptyText(
          review.reviewId,
          review.id,
          review.targetId,
        );
        const reviewSnapshot = {
          reviewId: reviewIdSnapshot,
          driverName: driverNameSnapshot,
          parentName: parentNameSnapshot,
          rating: ratingSnapshot,
          comment: commentSnapshot,
        };

        await softDeleteDocument("reviews", review.id, getDeletedBy(), {
          status: "removed_by_admin",
          auditSnapshot: reviewSnapshot,
        });
        await writeAuditLog({
          actionType: "Review Removed",
          performedBy: getPerformedBy(),
          performedByName: getPerformedByName(),
          performedByUid: getPerformedByUid(),
          targetType: "review",
          targetId: review.id,
          reviewId: reviewIdSnapshot,
          reviewSnapshot,
          driverName: driverNameSnapshot,
          parentName: parentNameSnapshot,
          reviewText: commentSnapshot,
          rating: ratingSnapshot,
          details: "A review was removed and moved to deleted records.",
        });
        success("Review removed.");
        return;
      }
      await updateDoc(doc(db, "reviews", review.id), {
        status: nextStatus,
        adminResponse: {
          message,
          status: nextStatus,
          respondedAt: serverTimestamp(),
        },
      });
      success("Review status updated.");
    } catch (e) {
      error("Failed to update review status.");
    } finally {
      setReviewActionLoadingId(null);
    }
  };

  const pendingDrivers = drivers.filter((d) =>
    d.status === "pending" || d.status === "inactive"
  );
  const verifiedDrivers = drivers.filter((d) => d.status === "active");
  const pendingRequests = allDriverRequests.filter(
    (r) => r.status === "pending",
  );
  const filteredReviews = reviews
    .filter((review) => {
      const sentiment = String(review.sentiment || "neutral").toLowerCase();
      const status = normalizeStatus(review.status);
      if (reviewFilter === "all") return true;
      if (reviewFilter === "positive") return sentiment === "positive";
      if (reviewFilter === "neutral") return sentiment === "neutral";
      if (reviewFilter === "negative") return sentiment === "negative";
      if (reviewFilter === "flagged") return status === "flagged";
      if (reviewFilter === "resolved") return status === "resolved";
      if (reviewFilter === "under_review") return status === "under_review";
      return true;
    })
    .sort((a, b) => {
      const aTime = a.createdAt?.toDate?.()?.getTime?.() || 0;
      const bTime = b.createdAt?.toDate?.()?.getTime?.() || 0;
      return bTime - aTime;
    });
  const paymentRows = [...payments].sort((a, b) => {
    const aTime = a.paidAt?.toDate?.()?.getTime?.() || 0;
    const bTime = b.paidAt?.toDate?.()?.getTime?.() || 0;
    return bTime - aTime;
  });
  const currentMonthKey = new Date().toISOString().slice(0, 7);
  const normalizedSalaryStatus = String(adminSalaryRecord?.status || "").trim().toLowerCase();
  const salaryStatus = adminSalaryRecord
    ? (normalizedSalaryStatus === "paid" ? "paid" : "pending")
    : "No salary record yet";
  const salaryPaidAt = adminSalaryRecord?.paidAt?.toDate
    ? adminSalaryRecord.paidAt.toDate().toLocaleDateString()
    : "—";
  const filteredPaymentRows = paymentRows.filter((p) => {
    if (paymentHistoryFilters.status !== "all" && (p.status || "pending") !== paymentHistoryFilters.status) return false;
    const parent = parents.find((pp) => pp.id === p.parentId);
    const parentName = String(parent?.name || p.parentName || p.parentId || "").toLowerCase();
    if (paymentHistoryFilters.parentName && !parentName.includes(paymentHistoryFilters.parentName.toLowerCase())) return false;

    const ride = ridesForPayments.find((r) => r.id === p.rideId);
    const driverName = String(
      ride?.driverName || drivers.find((d) => d.id === ride?.driverId)?.name || p.driverName || p.driverId || "",
    ).toLowerCase();
    if (paymentHistoryFilters.driverName && !driverName.includes(paymentHistoryFilters.driverName.toLowerCase())) return false;

    if (
      paymentHistoryFilters.transactionId &&
      !String(p.transactionId || "").toLowerCase().includes(paymentHistoryFilters.transactionId.toLowerCase())
    ) return false;

    if (paymentHistoryFilters.date) {
      const paidDate = p.paidAt?.toDate ? p.paidAt.toDate() : null;
      if (!paidDate) return false;
      const day = `${paidDate.getFullYear()}-${String(paidDate.getMonth() + 1).padStart(2, "0")}-${String(paidDate.getDate()).padStart(2, "0")}`;
      if (day !== paymentHistoryFilters.date) return false;
    }
    return true;
  });
  const formatTimeSlot = (rideMode) => {
    const mode = String(rideMode || "").trim().toLowerCase();
    if (mode === "morning") return "Morning";
    if (mode === "evening") return "Evening";
    return "Not set";
  };
  const formatPaymentDate = (payment) => {
    const value = payment.paymentDateTime || payment.paidAt;
    if (!value?.toDate) return "—";
    return value.toDate().toLocaleString();
  };
  const formatPaymentStatus = (status) => {
    const normalized = String(status || "pending").trim().toLowerCase();
    if (normalized === "paid") return "Paid";
    if (normalized === "pending") return "Pending";
    if (!normalized) return "Pending";
    return normalized.charAt(0).toUpperCase() + normalized.slice(1);
  };
  const formatPaymentMethod = (value) => {
    const normalized = String(value || "").trim().toLowerCase();
    if (!normalized) return "Stripe";
    if (normalized.includes("stripe")) return "Stripe Test Mode";
    return "Stripe";
  };
  const currentProfilePhotoUrl = profileImagePreview || adminProfile.profileImageUrl || "";

  const navItems = [
    {
      id: "dashboard",
      label: "Dashboard",
      icon: "M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 12a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1v-7z",
    },
    {
      id: "profile",
      label: "Profile",
      icon: "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z",
    },
    {
      id: "drivers",
      label: "Drivers",
      icon: "M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2",
    },
    {
      id: "parents",
      label: "Parents",
      icon: "M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z",
    },
    {
      id: "routes",
      label: "Routes & Schools",
      icon: "M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7",
    },
    {
      id: "payments",
      label: "Payments",
      icon: "M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z",
    },
    {
      id: "reviews_complaints",
      label: "Reviews & Complaints",
      icon: "M11.049 2.927c.3-.921 1.603-.921 1.902 0l2.037 6.27a1 1 0 00.95.69h6.592c.969 0 1.371 1.24.588 1.81l-5.334 3.876a1 1 0 00-.364 1.118l2.037 6.27c.3.922-.755 1.688-1.54 1.118l-5.334-3.876a1 1 0 00-1.176 0l-5.334 3.876c-.784.57-1.838-.196-1.539-1.118l2.037-6.27a1 1 0 00-.364-1.118L.88 11.697c-.783-.57-.38-1.81.588-1.81h6.592a1 1 0 00.951-.69l2.038-6.27z",
    },
    {
      id: "reports",
      label: "Reports",
      icon: "M9 17v-6m4 6V7m4 10v-3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z",
    },
    {
      id: "earnings",
      label: "Earnings",
      icon: "M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z",
    },
    {
      id: "logs",
      label: "Logs",
      icon: "M9 12h6m-6 4h6M7 4h10a2 2 0 012 2v12a2 2 0 01-2 2H7a2 2 0 01-2-2V6a2 2 0 012-2z",
    },
    {
      id: "deleted_records",
      label: "Deleted Records",
      icon: "M9 13h6m-7 4h8M7 7h10l-1 12H8L7 7zm3-3h4l1 2H9l1-2z",
    },
  ];

  return (
    <div className="flex flex-col md:flex-row min-h-screen bg-gradient-to-br from-slate-50 via-emerald-50/30 to-teal-50">
      {/* Sidebar */}
      <aside
        className={`${collapsed ? "w-full md:w-20" : "w-full md:w-72"} bg-gradient-to-b from-emerald-600 via-teal-600 to-cyan-700 shadow-2xl transition-all duration-300 relative flex-shrink-0`}
      >
        <div className="p-6">
          <div className="flex items-center justify-between mb-10">
            {!collapsed && (
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white shadow-lg">
                  <svg
                    className="w-7 h-7"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                    />
                  </svg>
                </div>
                <div>
                  <h2 className="text-xl font-bold text-white">Admin Panel</h2>
                  <p className="text-xs text-emerald-200">
                    Transport Management
                  </p>
                </div>
              </div>
            )}
            {collapsed && (
              <div className="flex items-center gap-3 -mb-10 md:hidden">
                <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white shadow-lg">
                  <svg
                    className="w-7 h-7"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z"
                    />
                  </svg>
                </div>
                <div>
                  <h2 className="text-xl font-bold text-white">Admin Panel</h2>
                  <p className="text-xs text-emerald-200">
                    Transport Management
                  </p>
                </div>
              </div>
            )}
          </div>

          <button
            onClick={() => setCollapsed(!collapsed)}
            className="absolute top-6 right-4 w-8 h-8 bg-white/10 hover:bg-white/20 rounded-lg flex items-center justify-center text-white transition-all hover:scale-110"
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
                d="M4 6h16M4 12h16M4 18h16"
              />
            </svg>
          </button>

          {!collapsed && (
            <div className="pt-2 pb-4 border-b border-white/20">
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 rounded-xl overflow-hidden bg-white/15 border border-white/20 flex-shrink-0 flex items-center justify-center">
                  {adminProfile.profileImageUrl ? (
                    <img
                      src={adminProfile.profileImageUrl}
                      alt="Admin profile"
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <span className="text-white font-semibold text-sm">
                      {(adminProfile.name || "A").slice(0, 1).toUpperCase()}
                    </span>
                  )}
                </div>
                <div className="min-w-0">
                  <p className="text-emerald-100 text-sm font-medium truncate">
                    {adminProfile.name || "Admin"}
                  </p>
                  <p className="text-emerald-200/80 text-xs truncate">
                    {adminProfile.phone || "—"}
                  </p>
                </div>
              </div>
            </div>
          )}

          <nav className={`space-y-1.5 mt-6 ${collapsed ? "hidden" : ""}`}>
            {navItems.map((item) => (
              <button
                key={item.id}
                onClick={() => setActiveTab(item.id)}
                className={`w-full text-left px-4 py-3 rounded-xl transition-all duration-300 flex items-center gap-3 ${activeTab === item.id
                    ? "bg-white text-emerald-700 shadow-lg font-semibold"
                    : "text-white hover:bg-white/10 hover:translate-x-1"
                  }`}
              >
                <svg
                  className="w-5 h-5 flex-shrink-0"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d={item.icon}
                  />
                </svg>
                {!collapsed && <span>{item.label}</span>}
              </button>
            ))}

            <div className="pt-4 mt-4 border-t border-white/20">
              <button
                onClick={logout}
                className="w-full text-left px-4 py-3 rounded-xl text-white hover:bg-red-500/30 transition-all flex items-center gap-3 hover:translate-x-1"
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
                    d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                  />
                </svg>
                {!collapsed && <span>Logout</span>}
              </button>
            </div>
          </nav>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 p-6 lg:p-8 overflow-auto">
        {/* ——— Dashboard ——— */}
        {activeTab === "dashboard" && (
          <div className="space-y-8">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div>
                <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                  Dashboard
                </h1>
                <p className="text-slate-600 mt-1">
                  Overview of your transport operations
                </p>
              </div>
              <p className="text-sm text-slate-500">
                {new Date().toLocaleDateString("en-US", {
                  weekday: "long",
                  year: "numeric",
                  month: "long",
                  day: "numeric",
                })}
              </p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-5">
              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Total Drivers
                    </p>
                    <p className="text-3xl font-bold text-slate-800 mt-1">
                      {drivers.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-emerald-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-emerald-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M8 7v8a2 2 0 002 2h6M8 7V5a2 2 0 012-2h4.586a1 1 0 01.707.293l4.414 4.414a1 1 0 01.293.707V15a2 2 0 01-2 2h-2M8 7H6a2 2 0 00-2 2v10a2 2 0 002 2h8a2 2 0 002-2v-2"
                      />
                    </svg>
                  </div>
                </div>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Total Parents
                    </p>
                    <p className="text-3xl font-bold text-slate-800 mt-1">
                      {parents.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-teal-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-teal-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z"
                      />
                    </svg>
                  </div>
                </div>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Pending Drivers
                    </p>
                    <p className="text-3xl font-bold text-amber-600 mt-1">
                      {pendingDrivers.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-amber-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-amber-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                      />
                    </svg>
                  </div>
                </div>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 hover:shadow-xl transition-shadow">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-slate-500 text-sm font-medium">
                      Pending Requests
                    </p>
                    <p className="text-3xl font-bold text-cyan-600 mt-1">
                      {pendingRequests.length}
                    </p>
                  </div>
                  <div className="w-14 h-14 bg-cyan-100 rounded-2xl flex items-center justify-center">
                    <svg
                      className="w-8 h-8 text-cyan-600"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth="2"
                        d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2"
                      />
                    </svg>
                  </div>
                </div>
              </div>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
                <h3 className="text-lg font-semibold text-slate-800 mb-4">
                  Quick stats
                </h3>
                <ul className="space-y-3">
                  <li className="flex justify-between items-center py-2 border-b border-slate-100">
                    <span className="text-slate-600">Verified drivers</span>
                    <span className="font-semibold text-emerald-600">
                      {verifiedDrivers.length}
                    </span>
                  </li>
                  <li className="flex justify-between items-center py-2 border-b border-slate-100">
                    <span className="text-slate-600">Routes</span>
                    <span className="font-semibold text-slate-800">
                      {routes.length}
                    </span>
                  </li>
                  <li className="flex justify-between items-center py-2">
                    <span className="text-slate-600">Schools</span>
                    <span className="font-semibold text-slate-800">
                      {schools.length}
                    </span>
                  </li>
                </ul>
              </div>
              <div className="bg-gradient-to-br from-emerald-500 to-teal-600 rounded-2xl p-6 shadow-lg text-white">
                <h3 className="text-lg font-semibold mb-2">Need to act</h3>
                <p className="text-emerald-100 text-sm mb-4">
                  {pendingDrivers.length > 0 || pendingRequests.length > 0
                    ? `You have ${pendingDrivers.length} driver(s) and ${pendingRequests.length} request(s) waiting for approval.`
                    : "All caught up. No pending approvals."}
                </p>
                {(pendingDrivers.length > 0 || pendingRequests.length > 0) && (
                  <button
                    onClick={() =>
                      setActiveTab(
                        pendingDrivers.length > 0 ? "drivers" : "parents",
                      )
                    }
                    className="px-4 py-2 bg-white text-emerald-700 rounded-xl font-medium hover:bg-emerald-50 transition"
                  >
                    Go to approvals
                  </button>
                )}
              </div>
            </div>
          </div>
        )}

        {/* ——— Profile ——— */}
        {activeTab === "profile" && (
          <div className="space-y-6 max-w-2xl">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Profile
              </h1>
              <p className="text-slate-600 mt-1">Update your admin details</p>
            </div>

            <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100 space-y-5">
              <div className="rounded-2xl border border-slate-100 bg-slate-50/70 p-4 sm:p-5">
                <div className="flex flex-col sm:flex-row sm:items-center gap-4">
                  <button
                    type="button"
                    onClick={() => currentProfilePhotoUrl && setIsProfilePhotoModalOpen(true)}
                    disabled={!currentProfilePhotoUrl}
                    className="w-24 h-24 rounded-2xl overflow-hidden bg-emerald-100 border border-emerald-200 flex items-center justify-center disabled:cursor-not-allowed"
                    title={currentProfilePhotoUrl ? "View profile photo" : "No profile photo available"}
                  >
                    {currentProfilePhotoUrl ? (
                      <img
                        src={currentProfilePhotoUrl}
                        alt="Admin profile"
                        className="w-full h-full object-cover"
                      />
                    ) : (
                      <svg
                        className="w-10 h-10 text-emerald-700"
                        fill="none"
                        stroke="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          strokeWidth="2"
                          d="M5.121 17.804A9 9 0 1118.88 17.8M15 11a3 3 0 11-6 0 3 3 0 016 0z"
                        />
                      </svg>
                    )}
                  </button>

                  <div className="flex-1 space-y-3">
                    <p className="text-sm font-medium text-slate-700">Profile photo</p>
                    <div className="flex flex-wrap gap-2">
                      <input
                        ref={profileImageInputRef}
                        type="file"
                        accept="image/png,image/jpeg,image/jpg"
                        onChange={onProfileImageFileChange}
                        className="hidden"
                      />
                      <button
                        type="button"
                        onClick={() => profileImageInputRef.current?.click()}
                        className="px-4 py-2 rounded-lg bg-white border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-50 transition"
                      >
                        Change Profile Photo
                      </button>
                      <button
                        type="button"
                        onClick={() => currentProfilePhotoUrl && setIsProfilePhotoModalOpen(true)}
                        disabled={!currentProfilePhotoUrl}
                        className="px-4 py-2 rounded-lg bg-slate-100 border border-slate-200 text-slate-700 text-sm font-medium hover:bg-slate-200 disabled:opacity-60 disabled:cursor-not-allowed transition"
                      >
                        View Photo
                      </button>
                      {selectedProfileImageFile && (
                        <>
                          <button
                            type="button"
                            onClick={uploadProfileImage}
                            disabled={uploadingProfileImage}
                            className="px-4 py-2 rounded-lg bg-emerald-500 text-white text-sm font-medium hover:bg-emerald-600 disabled:opacity-70 transition"
                          >
                            {uploadingProfileImage ? "Uploading..." : "Upload Photo"}
                          </button>
                          <button
                            type="button"
                            onClick={cancelProfileImageSelection}
                            className="px-4 py-2 rounded-lg bg-slate-100 text-slate-700 text-sm font-medium hover:bg-slate-200 disabled:opacity-70 transition"
                          >
                            {uploadingProfileImage ? "Cancel Upload" : "Cancel"}
                          </button>
                        </>
                      )}
                    </div>
                    <p className="text-xs text-slate-500">
                      JPG or PNG, max size 2MB.
                    </p>
                  </div>
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  Name
                </label>
                <input
                  value={adminProfile.name}
                  onChange={(e) =>
                    setAdminProfile({ ...adminProfile, name: e.target.value })
                  }
                  className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition"
                  placeholder="Your name"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  Phone (Pakistan)
                </label>
                <div className="flex">
                  <span className="inline-flex items-center gap-1 px-3 py-3 rounded-l-xl border border-r-0 border-slate-200 bg-slate-50 text-sm text-slate-700">
                    <span role="img" aria-label="Pakistan flag">
                      🇵🇰
                    </span>
                    +92
                  </span>
                  <input
                    value={(adminProfile.phone || "").replace(/^\+92/, "")}
                    onChange={(e) => {
                      const digits = e.target.value.replace(/\D/g, "").slice(0, 10);
                      setAdminProfile({
                        ...adminProfile,
                        phone: digits ? `+92${digits}` : "",
                      });
                    }}
                    className="w-full px-4 py-3 border border-slate-200 border-l-0 rounded-r-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition"
                    placeholder="3XX XXXXXXX"
                    inputMode="numeric"
                  />
                </div>
                <p className="mt-1 text-xs text-slate-500">
                  Enter a valid Pakistani mobile number, e.g. 3XX XXXXXXX.
                </p>
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  CNIC
                </label>
                <input
                  value={adminProfile.cnic}
                  onChange={(e) =>
                    setAdminProfile({ ...adminProfile, cnic: e.target.value })
                  }
                  className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition"
                  placeholder="CNIC"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-slate-700 mb-2">
                  City
                </label>
                <select
                  value={adminProfile.city}
                  onChange={(e) =>
                    setAdminProfile({ ...adminProfile, city: e.target.value })
                  }
                  className="w-full px-4 py-3 border border-slate-200 rounded-xl focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400 transition bg-white"
                >
                  <option>Abbottabad</option>
                  <option>Mansehra</option>
                  <option>Rawalpindi</option>
                </select>
              </div>
              <button
                onClick={saveAdminProfile}
                disabled={savingProfile || uploadingProfileImage}
                className="px-6 py-3 bg-gradient-to-r from-emerald-500 to-teal-600 text-white rounded-xl font-semibold shadow-lg hover:shadow-xl transition disabled:opacity-70"
              >
                {savingProfile ? "Saving…" : "Save profile"}
              </button>
            </div>
          </div>
        )}

        {/* ——— Drivers ——— */}
        {activeTab === "drivers" && (
          <div className="space-y-8">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Drivers
              </h1>
              <p className="text-slate-600 mt-1">Approve and manage drivers</p>
            </div>

            <section>
              <h2 className="text-xl font-semibold text-slate-800 mb-4 flex items-center gap-2">
                <span className="w-8 h-8 bg-amber-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-4 h-4 text-amber-600"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </span>
                Pending approval ({pendingDrivers.length})
              </h2>
              {pendingDrivers.length === 0 ? (
                <div className="bg-slate-50 rounded-2xl p-8 text-center text-slate-500">
                  No pending drivers. New registrations will appear here.
                </div>
              ) : (
                <div className="grid gap-4">
                  {pendingDrivers.map((driver) => (
                    <div
                      key={driver.id}
                      className="bg-white rounded-2xl p-4 sm:p-5 shadow-md border border-slate-100 flex flex-col gap-4 min-w-0 overflow-hidden"
                    >
                      <div className="flex items-center gap-3 min-w-0">
                        <div className="w-10 h-10 sm:w-12 sm:h-12 flex-shrink-0 bg-emerald-100 rounded-xl flex items-center justify-center text-emerald-700 font-bold text-lg">
                          {(driver.name || "D")[0]}
                        </div>
                        <div className="min-w-0 flex-1">
                          <p className="font-semibold text-slate-800 truncate">
                            {driver.name || "—"}
                          </p>
                          <p className="text-sm text-slate-500 truncate">
                            {driver.phone || driver.email}
                          </p>
                        </div>
                      </div>
                      <div className="flex flex-col sm:flex-row sm:flex-wrap gap-3 border-t border-slate-100 pt-4 sm:pt-0 sm:border-t-0">
                        <div className="flex flex-col sm:flex-row gap-2 min-w-0">
                          <select
                            value={driver.route || ""}
                            onChange={async (e) => {
                              await updateDoc(doc(db, "users", driver.id), {
                                route: e.target.value,
                              });
                            }}
                            className="w-full min-w-0 sm:w-40 px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-emerald-400 bg-white"
                          >
                            <option value="">Route</option>
                            {routes.map((r) => (
                              <option key={r.id} value={r.name}>
                                {r.name}
                              </option>
                            ))}
                          </select>
                          <select
                            value={driver.school || ""}
                            onChange={async (e) => {
                              await updateDoc(doc(db, "users", driver.id), {
                                school: e.target.value,
                              });
                            }}
                            className="w-full min-w-0 sm:w-40 px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-emerald-400 bg-white"
                          >
                            <option value="">School</option>
                            {schools.map((s) => (
                              <option key={s.id} value={s.name}>
                                {s.name}
                              </option>
                            ))}
                          </select>
                        </div>
                        <div className="flex gap-2 flex-shrink-0">
                          <button
                            onClick={() => approveDriver(driver.id)}
                            className="flex-1 sm:flex-none px-4 py-2 bg-emerald-500 text-white rounded-lg font-medium hover:bg-emerald-600 transition text-sm whitespace-nowrap"
                          >
                            Approve
                          </button>
                          <button
                            onClick={() => rejectDriver(driver.id)}
                            className="flex-1 sm:flex-none px-4 py-2 bg-red-500 text-white rounded-lg font-medium hover:bg-red-600 transition text-sm whitespace-nowrap"
                          >
                            Reject
                          </button>
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </section>

            <section>
              <h2 className="text-xl font-semibold text-slate-800 mb-4 flex items-center gap-2">
                <span className="w-8 h-8 bg-emerald-100 rounded-lg flex items-center justify-center">
                  <svg
                    className="w-4 h-4 text-emerald-600"
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
                </span>
                Verified drivers ({verifiedDrivers.length})
              </h2>
              {verifiedDrivers.length === 0 ? (
                <div className="bg-slate-50 rounded-2xl p-8 text-center text-slate-500">
                  No verified drivers yet.
                </div>
              ) : (
                <div className="grid gap-4">
                  {verifiedDrivers.map((driver) => {
                    const actualAssigned = parents.flatMap(p => (p.children || []).filter(c => c.assignedDriver === driver.id)).length;
                    const totalSeats = parseInt(driver.seats) || 0;
                    return (
                      <div
                        key={driver.id}
                        className="bg-white rounded-2xl p-5 shadow-md border border-slate-100 flex flex-wrap items-center justify-between gap-4"
                      >
                        <div className="flex items-center gap-4">
                          <div className="w-12 h-12 bg-teal-100 rounded-xl flex items-center justify-center text-teal-700 font-bold text-lg">
                            {(driver.name || "D")[0]}
                          </div>
                          <div>
                            <p className="font-semibold text-slate-800">
                              {driver.name || "—"}
                            </p>
                            <p className="text-sm text-slate-500">
                              {driver.route} · {driver.school}
                            </p>
                            <p className="text-xs text-slate-400">
                              Seats: {actualAssigned} / {totalSeats || "—"}
                            </p>
                          </div>
                        </div>
                        <div className="flex gap-2">
                          <button
                            onClick={() => setSelectedDriver(driver)}
                            className="px-4 py-2 bg-slate-100 text-slate-700 rounded-lg font-medium hover:bg-slate-200 transition"
                          >
                            Details
                          </button>
                          <button
                            onClick={() => removeDriver(driver.id, driver.name)}
                            className="px-4 py-2 bg-red-50 text-red-600 rounded-lg font-medium hover:bg-red-100 transition"
                          >
                            Remove
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </section>

            {selectedDriver && (
              <div
                className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
                onClick={() => setSelectedDriver(null)}
              >
                <div
                  className="bg-white rounded-2xl p-6 max-w-md w-full shadow-2xl max-h-[90vh] flex flex-col"
                  onClick={(e) => e.stopPropagation()}
                >
                  <h3 className="text-xl font-semibold text-slate-800 mb-4">
                    Driver details
                  </h3>
                  <div className="flex-1 overflow-y-auto pr-1 space-y-4">
                    <dl className="space-y-2 text-sm">
                      <div>
                        <dt className="text-slate-500">Name</dt>
                        <dd className="font-medium">{selectedDriver.name}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Phone</dt>
                        <dd className="font-medium">{selectedDriver.phone}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Vehicle</dt>
                        <dd className="font-medium">
                          {selectedDriver.vehicleName || "—"}
                        </dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Route</dt>
                        <dd className="font-medium">{selectedDriver.route}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">School</dt>
                        <dd className="font-medium">{selectedDriver.school}</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Total Capacity</dt>
                        <dd className="font-medium">{selectedDriver.seats || "—"} seats</dd>
                      </div>
                      <div>
                        <dt className="text-slate-500">Seat Status (Real-time)</dt>
                        <dd className="font-medium flex items-center gap-2">
                          <span>
                            {parents.flatMap(p => (p.children || []).filter(c => c.assignedDriver === selectedDriver.id)).length} assigned,{" "}
                            {(parseInt(selectedDriver.seats) || 0) - parents.flatMap(p => (p.children || []).filter(c => c.assignedDriver === selectedDriver.id)).length} available
                          </span>
                          <button
                            onClick={() => syncDriverSeats(selectedDriver)}
                            className="text-[10px] bg-emerald-100 text-emerald-700 px-2 py-1 rounded hover:bg-emerald-200 transition"
                            title="Update database counts to match these numbers"
                          >
                            Sync DB
                          </button>
                        </dd>
                      </div>
                    </dl>

                    {/* Assigned Children List */}
                    {parents.flatMap(p =>
                      (p.children || [])
                        .filter(c => c.assignedDriver === selectedDriver.id)
                        .map(c => ({ ...c, parentName: p.name }))
                    ).length > 0 && (
                        <div className="mt-4 pt-4 border-t border-slate-100">
                          <h4 className="text-sm font-semibold text-slate-700 mb-3 flex items-center gap-2">
                            <svg className="w-4 h-4 text-emerald-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                            </svg>
                            Assigned Children
                          </h4>
                          <div className="space-y-2">
                            {parents.flatMap(p =>
                              (p.children || [])
                                .filter(c => c.assignedDriver === selectedDriver.id)
                                .map(c => ({ ...c, parentName: p.name }))
                            ).map((child, idx) => (
                              <div key={idx} className="bg-slate-50 p-3 rounded-xl border border-slate-100 flex items-center justify-between gap-2">
                                <div>
                                  <p className="font-medium text-slate-800 text-xs">{child.name}</p>
                                  <p className="text-[10px] text-slate-500">{child.school}</p>
                                </div>
                                <div className="text-right">
                                  <p className="text-[10px] font-medium text-slate-600">{child.parentName}</p>
                                  <p className="text-[9px] text-emerald-600 font-medium bg-emerald-50 px-1.5 py-0.5 rounded-full inline-block">Assigned</p>
                                </div>
                              </div>
                            ))}
                          </div>
                        </div>
                      )}
                    {(selectedDriver.profilePic ||
                      selectedDriver.cnicPic ||
                      selectedDriver.licensePic ||
                      selectedDriver.vehiclePic) && (
                        <div className="mt-2 space-y-3">
                          <h4 className="text-sm font-semibold text-slate-700">
                            Documents & photos
                          </h4>
                          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                            {selectedDriver.profilePic && (
                              <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                                <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                  Profile photo
                                </div>
                                <a
                                  href={selectedDriver.profilePic}
                                  target="_blank"
                                  rel="noreferrer"
                                >
                                  <img
                                    src={selectedDriver.profilePic}
                                    alt="Driver profile"
                                    className="w-full h-32 object-cover"
                                  />
                                </a>
                              </div>
                            )}
                            {selectedDriver.cnicPic && (
                              <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                                <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                  CNIC
                                </div>
                                <a
                                  href={selectedDriver.cnicPic}
                                  target="_blank"
                                  rel="noreferrer"
                                >
                                  <img
                                    src={selectedDriver.cnicPic}
                                    alt="Driver CNIC"
                                    className="w-full h-32 object-cover"
                                  />
                                </a>
                              </div>
                            )}
                            {selectedDriver.licensePic && (
                              <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                                <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                  License
                                </div>
                                <a
                                  href={selectedDriver.licensePic}
                                  target="_blank"
                                  rel="noreferrer"
                                >
                                  <img
                                    src={selectedDriver.licensePic}
                                    alt="Driver license"
                                    className="w-full h-32 object-cover"
                                  />
                                </a>
                              </div>
                            )}
                            {selectedDriver.vehiclePic && (
                              <div className="border border-slate-200 rounded-xl overflow-hidden bg-slate-50">
                                <div className="px-3 py-2 text-xs font-medium text-slate-600">
                                  Vehicle
                                </div>
                                <a
                                  href={selectedDriver.vehiclePic}
                                  target="_blank"
                                  rel="noreferrer"
                                >
                                  <img
                                    src={selectedDriver.vehiclePic}
                                    alt="Driver vehicle"
                                    className="w-full h-32 object-cover"
                                  />
                                </a>
                              </div>
                            )}
                          </div>
                        </div>
                      )}
                    <div className="mt-2">
                      <h4 className="text-sm font-semibold text-slate-700 mb-2">
                        Live location
                      </h4>
                      {selectedDriverLocation ? (
                        <>
                          <div className="text-xs text-slate-500 mb-2">
                            Lat: {selectedDriverLocation.lat.toFixed(5)}, Lng:{" "}
                            {selectedDriverLocation.lng.toFixed(5)}
                          </div>
                          <div
                            ref={mapRef}
                            className="w-full h-64 rounded-xl border border-slate-200 overflow-hidden"
                          />
                        </>
                      ) : (
                        <p className="text-xs text-slate-500">
                          Waiting for driver GPS updates. Make sure the driver has started a ride in the app.
                        </p>
                      )}
                    </div>
                  </div>

                  <button
                    onClick={() => setSelectedDriver(null)}
                    className="mt-6 w-full py-2 bg-slate-100 text-slate-700 rounded-xl font-medium hover:bg-slate-200 transition"
                  >
                    Close
                  </button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* ——— Parents ——— */}
        {activeTab === "parents" && (
          <div className="space-y-8">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Parents & children
              </h1>
              <p className="text-slate-600 mt-1">
                Manage parents and assign drivers to children
              </p>
            </div>

            {/* Pending requests first */}
            {pendingRequests.length > 0 && (
              <section>
                <h2 className="text-xl font-semibold text-slate-800 mb-4">
                  Parent driver requests
                </h2>
                <div className="space-y-3">
                  {pendingRequests.map((req) => (
                    <div
                      key={req.id}
                      className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4 min-w-0 overflow-hidden"
                    >
                      <div className="min-w-0 flex-1">
                        <p className="font-medium text-slate-800 truncate">
                          {req.parentName}
                        </p>
                        <p className="text-sm text-slate-600 break-words mt-0.5">
                          Driver:{" "}
                          {drivers.find((d) => d.id === req.driverId)?.name ||
                            "—"}{" "}
                          · Children: {req.childIds?.join(", ")}
                        </p>
                      </div>
                      <div className="flex gap-2 flex-shrink-0">
                        <button
                          onClick={() => approveRequest(req)}
                          className="flex-1 sm:flex-none px-4 py-2 bg-emerald-500 text-white rounded-lg font-medium hover:bg-emerald-600 transition text-sm whitespace-nowrap"
                        >
                          Approve
                        </button>
                        <button
                          onClick={() => rejectRequest(req.id)}
                          className="flex-1 sm:flex-none px-4 py-2 bg-red-500 text-white rounded-lg font-medium hover:bg-red-600 transition text-sm whitespace-nowrap"
                        >
                          Reject
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              </section>
            )}

            <section>
              <h2 className="text-xl font-semibold text-slate-800 mb-4">
                All parents
              </h2>
              {parents.length === 0 ? (
                <div className="bg-slate-50 rounded-2xl p-8 text-center text-slate-500">
                  No parents yet.
                </div>
              ) : (
                <div className="grid gap-4">
                  {parents.map((parent) => (
                    <div
                      key={parent.id}
                      className="bg-white rounded-2xl border border-slate-100 shadow-md overflow-hidden"
                    >
                      <div className="p-5 flex flex-wrap items-center justify-between gap-4">
                        <div className="flex items-center gap-4">
                          <div className="w-12 h-12 bg-teal-100 rounded-xl flex items-center justify-center text-teal-700 font-bold text-lg">
                            {(parent.name || "P")[0]}
                          </div>
                          <div>
                            <p className="font-semibold text-slate-800 text-lg">
                              {parent.name || "—"}
                            </p>
                            <div className="flex flex-wrap gap-x-4 gap-y-1 text-sm text-slate-500 mt-1">
                              <span className="flex items-center gap-1">
                                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                                </svg>
                                {parent.phone}
                              </span>
                              {(parent.latitude && parent.longitude) && (
                                <span className="flex items-center gap-1">
                                  <svg className="w-4 h-4 text-rose-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                  </svg>
                                  Loc: {parent.latitude.toFixed(4)}, {parent.longitude.toFixed(4)}
                                </span>
                              )}
                            </div>
                          </div>
                        </div>
                        <div className="flex gap-2">
                          <button
                            onClick={() => {
                              setSelectedParent(parent);
                              fetchChildren(parent);
                            }}
                            className="px-4 py-2 bg-emerald-500 text-white rounded-lg font-medium hover:bg-emerald-600 transition"
                          >
                            Children & assign driver
                          </button>
                          <button
                            onClick={() => removeParent(parent.id, parent.name)}
                            className="px-4 py-2 bg-red-50 text-red-600 rounded-lg font-medium hover:bg-red-100 transition"
                          >
                            Remove
                          </button>
                        </div>
                      </div>

                      {selectedParent?.id === parent.id && (
                        <div className="border-t border-slate-100 bg-slate-50/50 p-5">
                          <h4 className="font-medium text-slate-700 mb-3">
                            {parent.name}'s children
                          </h4>
                          {parentChildren.length === 0 ? (
                            <p className="text-slate-500 text-sm">
                              No children added.
                            </p>
                          ) : (
                            <div className="space-y-3">
                              {parentChildren.map((child, index) => (
                                <div
                                  key={child.id}
                                  className="flex flex-col gap-4 bg-white rounded-2xl p-5 border border-slate-100 shadow-sm transition-hover hover:shadow-md"
                                >
                                  <div className="flex items-start gap-4">
                                    <div className="w-16 h-16 flex-shrink-0">
                                      {(child.image || child.profilePic || child.photoUrl || child.photo || child.profilePhoto || child.childPhoto || child.profile_photo) ? (
                                        <a
                                          href={child.image || child.profilePic || child.photoUrl || child.photo || child.profilePhoto || child.childPhoto || child.profile_photo}
                                          target="_blank"
                                          rel="noreferrer"
                                          className="w-full h-full block bg-slate-100 rounded-xl overflow-hidden border border-slate-200 hover:ring-2 hover:ring-emerald-400 transition-all cursor-pointer"
                                          title="Click to open full photo"
                                        >
                                          <img
                                            src={child.image || child.profilePic || child.photoUrl || child.photo || child.profilePhoto || child.childPhoto || child.profile_photo}
                                            alt={child.name}
                                            className="w-full h-full object-cover"
                                          />
                                        </a>
                                      ) : (
                                        <div className="w-full h-full bg-slate-100 rounded-xl overflow-hidden border border-slate-200 flex items-center justify-center text-slate-300">
                                          <svg className="w-8 h-8" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                                          </svg>
                                        </div>
                                      )}
                                    </div>
                                    <div className="flex-1">
                                      <div className="flex justify-between items-start">
                                        <h5 className="font-bold text-slate-800 text-lg flex items-center gap-2">
                                          {child.name}
                                          {child.gender && (
                                            <span className={`text-[10px] px-1.5 py-0.5 rounded-md ${child.gender.toLowerCase() === 'female' ? 'bg-pink-100 text-pink-600' : 'bg-blue-100 text-blue-600'}`}>
                                              {child.gender}
                                            </span>
                                          )}
                                        </h5>
                                        <div className="flex gap-2">
                                          {child.age && (
                                            <span className="text-xs bg-slate-100 text-slate-600 px-2 py-1 rounded-full font-semibold">
                                              {child.age} yrs
                                            </span>
                                          )}
                                          {(child.class || child.grade) && (
                                            <span className="text-xs bg-indigo-50 text-indigo-600 px-2 py-1 rounded-full font-semibold">
                                              {child.class || child.grade}
                                            </span>
                                          )}
                                        </div>
                                      </div>
                                      <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-4 gap-y-2 mt-2">
                                        <p className="text-sm text-slate-600 flex items-center gap-1.5">
                                          <svg className="w-4 h-4 text-emerald-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-7h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" />
                                          </svg>
                                          {child.school}
                                        </p>
                                        <div className="flex flex-wrap gap-x-3 gap-y-1">
                                          {(child.schoolTiming || child.timing || child.schoolTime) && (
                                            <p className="text-xs text-slate-500 flex items-center gap-1">
                                              <svg className="w-3 h-3 text-amber-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
                                              </svg>
                                              Time: {child.schoolTiming || child.timing || child.schoolTime}
                                            </p>
                                          )}
                                          {(child.onTime || child.pickupTime || child.morningTiming || child.on_time || child.school_on_time) && (
                                            <p className="text-xs text-slate-500 flex items-center gap-1">
                                              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400"></span>
                                              On: {child.onTime || child.pickupTime || child.morningTiming || child.on_time || child.school_on_time}
                                            </p>
                                          )}
                                          {(child.offTime || child.dropoffTime || child.eveningTiming || child.off_time || child.school_off_time) && (
                                            <p className="text-xs text-slate-500 flex items-center gap-1">
                                              <span className="w-1.5 h-1.5 rounded-full bg-rose-400"></span>
                                              Off: {child.offTime || child.dropoffTime || child.eveningTiming || child.off_time || child.school_off_time}
                                            </p>
                                          )}
                                        </div>
                                        {child.route && (
                                          <p className="text-sm text-slate-600 flex items-center gap-1.5 sm:col-span-2">
                                            <svg className="w-4 h-4 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 20l-5.447-2.724A1 1 0 013 16.382V5.618a1 1 0 011.447-.894L9 7m0 13l6-3m-6 3V7m6 10l4.553 2.276A1 1 0 0021 18.382V7.618a1 1 0 00-.553-.894L15 4m0 13V4m0 0L9 7" />
                                            </svg>
                                            {child.route}
                                          </p>
                                        )}
                                        {child.address && (
                                          <p className="text-xs text-slate-500 flex items-center gap-1.5 sm:col-span-2">
                                            <svg className="w-3.5 h-3.5 text-slate-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17.657 16.657L13.414 20.9a1.998 1.998 0 01-2.827 0l-4.244-4.243a8 8 0 1111.314 0z" />
                                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 11a3 3 0 11-6 0 3 3 0 016 0z" />
                                            </svg>
                                            Address: {child.address}
                                          </p>
                                        )}
                                        {(child.pickupPoint || child.dropoffPoint) && (
                                          <div className="text-xs text-slate-500 sm:col-span-2 flex flex-wrap gap-x-4">
                                            {child.pickupPoint && <span>Pickup: {child.pickupPoint}</span>}
                                            {child.dropoffPoint && <span>Dropoff: {child.dropoffPoint}</span>}
                                          </div>
                                        )}
                                        <div className="sm:col-span-2 pt-2 flex flex-wrap gap-4 border-t border-slate-50 mt-1">
                                          <div className="flex items-center gap-1 text-xs text-slate-500">
                                            <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                                            </svg>
                                            Parent: {parent.phone}
                                          </div>
                                          {child.emergencyContact && (
                                            <div className="flex items-center gap-1 text-xs text-rose-500 font-medium">
                                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                                              </svg>
                                              Emergency: {child.emergencyContact}
                                            </div>
                                          )}
                                        </div>
                                      </div>
                                    </div>
                                  </div>

                                  <div className="flex flex-wrap items-center justify-between gap-3 pt-3 border-t border-slate-50">
                                    <div className="text-sm">
                                      <span className="text-slate-500">Driver: </span>
                                      <span className="font-semibold text-emerald-700">
                                        {child.assignedDriver
                                          ? verifiedDrivers.find(
                                            (d) => d.id === child.assignedDriver,
                                          )?.name || "—"
                                          : "Unassigned"}
                                      </span>
                                    </div>
                                    <select
                                      value={child.assignedDriver || ""}
                                      onChange={(e) =>
                                        assignDriverToChild(
                                          selectedParent,
                                          index,
                                          e.target.value,
                                        )
                                      }
                                      className="px-3 py-2 border border-slate-200 rounded-lg text-sm focus:ring-2 focus:ring-emerald-400 bg-white"
                                    >
                                      <option value="">Select driver</option>
                                      {verifiedDrivers.map((d) => (
                                        <option key={d.id} value={d.id}>
                                          {d.name}
                                        </option>
                                      ))}
                                    </select>
                                  </div>
                                </div>
                              ))}
                            </div>
                          )}
                          <button
                            onClick={() => setSelectedParent(null)}
                            className="mt-4 text-sm text-slate-500 hover:text-slate-700"
                          >
                            Close
                          </button>
                        </div>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </section>
          </div>
        )}

        {/* ——— Routes & Schools ——— */}
        {activeTab === "routes" && (
          <div className="space-y-8">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Routes & schools
              </h1>
              <p className="text-slate-600 mt-1">
                Add and manage routes and schools
              </p>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
                <h3 className="text-lg font-semibold text-slate-800 mb-4">
                  Routes
                </h3>
                <div className="mb-4">
                  <button
                    type="button"
                    onClick={() => setAddRouteModalOpen(true)}
                    className="w-full sm:w-auto px-5 py-3 bg-emerald-500 text-white rounded-xl font-medium hover:bg-emerald-600 transition flex items-center justify-center gap-2"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                    </svg>
                    Add route (school → destination)
                  </button>
                </div>
                <ul className="space-y-2">
                  {routes.map((r) => (
                    <li
                      key={r.id}
                      className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-slate-50 gap-2"
                    >
                      <div className="min-w-0 flex-1">
                        <span className="font-medium text-slate-800 block truncate">
                          {r.name}
                        </span>
                        <div className="mt-1">
                          <label className="text-xs text-slate-500 mr-2">Fare (PKR)</label>
                          <input
                            type="number"
                            min="1"
                            step="0.01"
                            defaultValue={r.fare ?? ""}
                            onBlur={(e) => {
                              const nextFare = e.target.value;
                              if (!nextFare && r.fare == null) return;
                              if (Number(nextFare) === Number(r.fare)) return;
                              updateRouteFare(r.id, nextFare);
                            }}
                            className="w-28 px-2 py-1 text-xs border border-slate-200 rounded-md focus:ring-2 focus:ring-emerald-400 focus:border-emerald-400"
                          />
                        </div>
                        {(r.schoolName != null || r.destinationName != null) && (
                          <div className="text-xs text-slate-500 mt-0.5 space-y-0.5">
                            {r.schoolName != null && (
                              <span className="block truncate">
                                School: {r.schoolName}
                                {r.schoolLatitude != null && ` (${r.schoolLatitude.toFixed(4)}, ${r.schoolLongitude.toFixed(4)})`}
                              </span>
                            )}
                            {r.destinationName != null && (
                              <span className="block truncate">
                                Destination: {r.destinationName}
                                {r.destinationLatitude != null && ` (${r.destinationLatitude.toFixed(4)}, ${r.destinationLongitude.toFixed(4)})`}
                              </span>
                            )}
                          </div>
                        )}
                      </div>
                      <button
                        onClick={() => deleteRoute(r.id, r.name)}
                        className="text-red-500 hover:text-red-700 text-sm font-medium flex-shrink-0"
                      >
                        Delete
                      </button>
                    </li>
                  ))}
                  {routes.length === 0 && (
                    <li className="text-slate-500 text-sm py-2">
                      No routes yet. Add a route by selecting a school and destination.
                    </li>
                  )}
                </ul>
              </div>

              <div className="bg-white rounded-2xl p-6 shadow-lg border border-slate-100">
                <h3 className="text-lg font-semibold text-slate-800 mb-4">
                  Schools
                </h3>
                <div className="mb-4">
                  <button
                    type="button"
                    onClick={() => setAddSchoolMapOpen(true)}
                    className="w-full sm:w-auto px-5 py-3 bg-emerald-500 text-white rounded-xl font-medium hover:bg-emerald-600 transition flex items-center justify-center gap-2"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                    </svg>
                    Add school from map
                  </button>
                </div>
                <ul className="space-y-2">
                  {schools.map((s) => (
                    <li
                      key={s.id}
                      className="flex items-center justify-between py-2 px-3 rounded-lg hover:bg-slate-50 gap-2"
                    >
                      <div className="min-w-0 flex-1">
                        <span className="font-medium text-slate-800 block truncate">
                          {s.name}
                        </span>
                        {(s.latitude != null && s.longitude != null) && (
                          <span className="text-xs text-slate-500">
                            {s.latitude.toFixed(5)}, {s.longitude.toFixed(5)}
                          </span>
                        )}
                      </div>
                      <button
                        onClick={() => deleteSchool(s.id, s.name)}
                        className="text-red-500 hover:text-red-700 text-sm font-medium flex-shrink-0"
                      >
                        Delete
                      </button>
                    </li>
                  ))}
                  {schools.length === 0 && (
                    <li className="text-slate-500 text-sm py-2">
                      No schools yet. Add a school from map above.
                    </li>
                  )}
                </ul>
              </div>
            </div>
          </div>
        )}

        {/* ——— Payments ——— */}
        {activeTab === "payments" && (
          <div className="space-y-6">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Payments
              </h1>
              <p className="text-slate-600 mt-1">Manage parent payments</p>
            </div>
            <div className="bg-white rounded-2xl p-8 shadow-lg border border-slate-100">
              <h3 className="text-lg font-semibold text-slate-800 text-left mb-3">Payment History</h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-4">
                <input
                  value={paymentHistoryFilters.parentName}
                  onChange={(e) => setPaymentHistoryFilters((prev) => ({ ...prev, parentName: e.target.value }))}
                  placeholder="Filter parent name"
                  className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
                />
                <input
                  value={paymentHistoryFilters.driverName}
                  onChange={(e) => setPaymentHistoryFilters((prev) => ({ ...prev, driverName: e.target.value }))}
                  placeholder="Filter driver name"
                  className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
                />
                <input
                  value={paymentHistoryFilters.transactionId}
                  onChange={(e) => setPaymentHistoryFilters((prev) => ({ ...prev, transactionId: e.target.value }))}
                  placeholder="Filter transaction ID"
                  className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
                />
                <select
                  value={paymentHistoryFilters.status}
                  onChange={(e) => setPaymentHistoryFilters((prev) => ({ ...prev, status: e.target.value }))}
                  className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
                >
                  <option value="all">All statuses</option>
                  <option value="paid">Paid</option>
                  <option value="pending">Pending</option>
                </select>
                <input
                  type="date"
                  value={paymentHistoryFilters.date}
                  onChange={(e) => setPaymentHistoryFilters((prev) => ({ ...prev, date: e.target.value }))}
                  className="px-3 py-2 border border-slate-200 rounded-lg text-sm"
                  title="Filter payment date"
                />
              </div>
              <div className="overflow-x-auto rounded-xl border border-slate-200">
                <table className="min-w-[1520px] w-full text-sm border-collapse">
                  <thead>
                    <tr className="border-b border-slate-200">
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Parent Name</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Driver Name</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Route</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Time Slot</th>
                      <th className="px-3 py-2 text-right border border-slate-200 bg-slate-50">Amount</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Payment Status</th>
                      <th className="px-3 py-2 text-center border border-slate-200 bg-slate-50">Driver Paid</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Payment Date</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Transaction ID</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Stripe PaymentIntent ID</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Payment Method</th>
                      <th className="px-3 py-2 text-left border border-slate-200 bg-slate-50">Action</th>
                    </tr>
                  </thead>
                  <tbody>
                    {paymentsLoading || ledgerLoading ? (
                      <tr>
                        <td className="py-3 px-3 border border-slate-200 text-center text-slate-500" colSpan={12}>
                          Loading payments...
                        </td>
                      </tr>
                    ) : (
                      <>
                        {filteredPaymentRows.map((p) => {
                          const parent = parents.find((pp) => pp.id === p.parentId);
                          const ride = ridesForPayments.find((r) => r.id === p.rideId);
                          const driver = drivers.find((d) => d.id === (ride?.driverId || p.driverId));
                          const isPaid = p.status === "paid";
                          const driverPaid = ledgerEntries.some((le) => le.rideId === p.rideId);
                          const parentName = parent?.name || p.parentName || p.parentId || "—";
                          const driverName =
                            ride?.driverName || driver?.name || p.driverName || p.driverId || "—";
                          const routeName = ride?.route || ride?.routeName || "—";
                          const timeSlot = formatTimeSlot(ride?.rideMode || ride?.timeSlot);
                          const amount = Number(p.amount ?? ride?.fare ?? 0).toFixed(2);
                          return (
                            <tr key={`hist-${p.id}`} className="border-b border-slate-100">
                              <td className="px-3 py-2 border border-slate-200">{parentName}</td>
                              <td className="px-3 py-2 border border-slate-200">{driverName}</td>
                              <td className="px-3 py-2 border border-slate-200">{routeName}</td>
                              <td className="px-3 py-2 border border-slate-200">{timeSlot}</td>
                              <td className="px-3 py-2 border border-slate-200 text-right">PKR {amount}</td>
                              <td className="px-3 py-2 border border-slate-200">{formatPaymentStatus(p.status)}</td>
                              <td className="px-3 py-2 border border-slate-200 text-center">{driverPaid ? "Yes" : "No"}</td>
                              <td className="px-3 py-2 border border-slate-200">{formatPaymentDate(p)}</td>
                              <td className="px-3 py-2 border border-slate-200">{p.transactionId || "—"}</td>
                              <td className="px-3 py-2 border border-slate-200">{p.stripePaymentIntentId || "—"}</td>
                              <td className="px-3 py-2 border border-slate-200">{formatPaymentMethod(p.paymentMethod || p.method)}</td>
                              <td className="px-3 py-2 border border-slate-200">
                                <button
                                  onClick={() => markPaymentPaid(p)}
                                  disabled={isPaid || markingPaidId === p.id}
                                  className="text-emerald-600 font-medium hover:underline disabled:text-slate-400 disabled:no-underline"
                                >
                                  {isPaid ? "Paid" : markingPaidId === p.id ? "Processing..." : "Mark paid"}
                                </button>
                              </td>
                            </tr>
                          );
                        })}
                        {filteredPaymentRows.length === 0 && (
                          <tr>
                            <td className="py-3 px-3 border border-slate-200 text-center text-slate-500" colSpan={12}>
                              No payment history matches filters.
                            </td>
                          </tr>
                        )}
                      </>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        {/* ——— Reviews & Complaints ——— */}
        {activeTab === "reviews_complaints" && (
          <div className="space-y-6">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Reviews & Complaints
              </h1>
              <p className="text-slate-600 mt-1">
                Moderate parent-driver feedback and flagged complaints
              </p>
            </div>

            <div className="bg-white rounded-2xl p-5 shadow-lg border border-slate-100">
              <div className="flex flex-wrap gap-2">
                {[
                  { id: "all", label: "All" },
                  { id: "positive", label: "Positive" },
                  { id: "neutral", label: "Neutral" },
                  { id: "negative", label: "Negative" },
                  { id: "flagged", label: "Flagged" },
                  { id: "resolved", label: "Resolved" },
                  { id: "under_review", label: "Under Review" },
                ].map((option) => (
                  <button
                    key={option.id}
                    onClick={() => setReviewFilter(option.id)}
                    className={`px-3 py-1.5 rounded-lg text-sm font-medium transition ${
                      reviewFilter === option.id
                        ? "bg-emerald-600 text-white"
                        : "bg-slate-100 text-slate-700 hover:bg-slate-200"
                    }`}
                  >
                    {option.label}
                  </button>
                ))}
              </div>
            </div>

            <div className="space-y-4">
              {reviewsLoading ? (
                <div className="bg-white rounded-2xl p-8 shadow-lg border border-slate-100 text-center text-slate-500">
                  Loading reviews...
                </div>
              ) : filteredReviews.length === 0 ? (
                <div className="bg-white rounded-2xl p-8 shadow-lg border border-slate-100 text-center text-slate-500">
                  No reviews found for selected filter.
                </div>
              ) : (
                filteredReviews.map((review) => {
                  const parent = parents.find((p) => p.id === review.parentId);
                  const driver = drivers.find((d) => d.id === review.driverId);
                  const status = normalizeStatus(review.status);
                  const sentiment = String(review.sentiment || "neutral")
                    .toLowerCase()
                    .trim();
                  const isFlagged = status === "flagged";
                  const isExpanded = !!expandedReviewIds[review.id];
                  const isActionLoading = reviewActionLoadingId === review.id;
                  const comment = String(review.comment || "");
                  const longComment = comment.length > 160;
                  const commentPreview =
                    longComment && !isExpanded
                      ? `${comment.slice(0, 160)}...`
                      : comment || "—";

                  let sentimentStyles =
                    "bg-amber-100 text-amber-700 border border-amber-200";
                  let sentimentLabel = "Neutral";
                  if (sentiment === "positive") {
                    sentimentStyles =
                      "bg-emerald-100 text-emerald-700 border border-emerald-200";
                    sentimentLabel = "Positive";
                  } else if (sentiment === "negative") {
                    sentimentStyles =
                      "bg-red-100 text-red-700 border border-red-200";
                    sentimentLabel = "Negative";
                  }

                  const statusLabelMap = {
                    active: "Active",
                    normal: "Normal",
                    flagged: "Flagged",
                    resolved: "Resolved",
                    dismissed: "Dismissed",
                    under_review: "Under Review",
                    deleted: "Deleted by Parent",
                    removed_by_admin: "Removed by Admin",
                  };

                  return (
                    <div
                      key={review.id}
                      className={`bg-white rounded-2xl p-5 shadow-lg border ${
                        isFlagged
                          ? "border-red-300 ring-1 ring-red-200"
                          : "border-slate-100"
                      }`}
                    >
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="space-y-1 text-sm text-slate-700">
                          <p>
                            <span className="font-semibold text-slate-900">
                              Parent:
                            </span>{" "}
                            {parent?.name || "Unknown Parent"}
                          </p>
                          <p>
                            <span className="font-semibold text-slate-900">
                              Driver:
                            </span>{" "}
                            {driver?.name || "Unknown Driver"}
                          </p>
                        </div>
                        <div className="flex flex-wrap gap-2 items-center">
                          <span className="px-2.5 py-1 rounded-full text-xs font-semibold bg-slate-100 text-slate-700 border border-slate-200">
                            {statusLabelMap[status] || "Normal"}
                          </span>
                          {isFlagged && (
                            <span className="px-2.5 py-1 rounded-full text-xs font-semibold bg-red-100 text-red-700 border border-red-200">
                              FLAGGED BY DRIVER
                            </span>
                          )}
                        </div>
                      </div>

                      <div className="mt-4 flex flex-wrap gap-3 items-center text-sm text-slate-700">
                        <span className="font-medium text-slate-800">
                          Rating: {Number(review.rating || 0).toFixed(1)} ⭐
                        </span>
                        <span
                          className={`px-2.5 py-1 rounded-full text-xs font-semibold ${sentimentStyles}`}
                        >
                          {sentimentLabel}
                        </span>
                        <span className="text-xs text-slate-500">
                          {formatReviewDate(review.createdAt)}
                        </span>
                      </div>

                      <div className="mt-4">
                        <p className="text-sm text-slate-700 leading-relaxed break-words">
                          {commentPreview}
                        </p>
                        {longComment && (
                          <button
                            onClick={() => toggleReviewExpanded(review.id)}
                            className="mt-1 text-xs font-semibold text-emerald-600 hover:text-emerald-700"
                          >
                            {isExpanded ? "Show less" : "Show more"}
                          </button>
                        )}
                      </div>

                      <div className="mt-4 flex flex-wrap gap-2">
                        <button
                          onClick={() => updateReviewStatus(review, "under_review")}
                          disabled={isActionLoading}
                          className="px-3 py-2 rounded-lg text-sm font-medium bg-amber-100 text-amber-700 hover:bg-amber-200 disabled:opacity-60"
                        >
                          {isActionLoading ? "Updating..." : "Mark Under Review"}
                        </button>
                        <button
                          onClick={() => updateReviewStatus(review, "resolved")}
                          disabled={isActionLoading}
                          className="px-3 py-2 rounded-lg text-sm font-medium bg-emerald-100 text-emerald-700 hover:bg-emerald-200 disabled:opacity-60"
                        >
                          Resolve
                        </button>
                        <button
                          onClick={() => updateReviewStatus(review, "dismissed")}
                          disabled={isActionLoading}
                          className="px-3 py-2 rounded-lg text-sm font-medium bg-slate-200 text-slate-700 hover:bg-slate-300 disabled:opacity-60"
                        >
                          Dismiss
                        </button>
                        <button
                          onClick={() => updateReviewStatus(review, "removed_by_admin")}
                          disabled={isActionLoading}
                          className="px-3 py-2 rounded-lg text-sm font-medium bg-red-100 text-red-700 hover:bg-red-200 disabled:opacity-60"
                        >
                          Remove Review
                        </button>
                      </div>
                    </div>
                  );
                })
              )}
            </div>
          </div>
        )}

        {/* ——— Reports ——— */}
        {activeTab === "reports" && (
          <ReportsTab
            drivers={drivers}
            parents={parents}
            rides={ridesForPayments}
            reviews={reviews}
            payments={payments}
          />
        )}

        {/* ——— Earnings ——— */}
        {activeTab === "earnings" && (
          <div className="space-y-6">
            <div>
              <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
                Earnings
              </h1>
              <p className="text-slate-600 mt-1">
                View earnings from payments collection
              </p>
            </div>
            <div className="bg-white rounded-2xl p-8 shadow-lg border border-slate-100 text-center">
              <div className="w-16 h-16 bg-cyan-100 rounded-2xl flex items-center justify-center mx-auto mb-4">
                <svg
                  className="w-8 h-8 text-cyan-600"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2"
                    d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                  />
                </svg>
              </div>
              <div className="space-y-2 text-slate-700">
                <p>Monthly Salary: PKR 35000</p>
                <p>Status: {salaryStatus}</p>
                <p>PaidAt: {salaryPaidAt}</p>
                <p>Current month: {currentMonthKey}</p>
              </div>
            </div>
          </div>
        )}

        {activeTab === "logs" && <LogsTab />}

        {activeTab === "deleted_records" && (
          <DeletedRecordsTab adminProfile={adminProfile} />
        )}
      </main>

      {isProfilePhotoModalOpen && currentProfilePhotoUrl && (
        <div
          className="fixed inset-0 z-50 bg-slate-900/70 backdrop-blur-sm flex items-center justify-center p-4"
          onClick={() => setIsProfilePhotoModalOpen(false)}
        >
          <div
            className="relative w-full max-w-3xl bg-white rounded-2xl shadow-2xl border border-slate-100 overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => setIsProfilePhotoModalOpen(false)}
              className="absolute top-3 right-3 z-10 w-10 h-10 rounded-full bg-white/90 hover:bg-slate-100 text-slate-700 flex items-center justify-center border border-slate-200 transition"
              aria-label="Close profile photo preview"
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
            <div className="bg-slate-50 flex items-center justify-center max-h-[80vh]">
              <img
                src={currentProfilePhotoUrl}
                alt="Admin profile preview"
                className="w-full h-auto max-h-[80vh] object-contain"
              />
            </div>
          </div>
        </div>
      )}

      <AddSchoolMapModal
        isOpen={addSchoolMapOpen}
        onClose={() => setAddSchoolMapOpen(false)}
        onSelectSchool={addSchoolFromMap}
        isAdding={addingSchool}
      />

      <AddRouteModal
        isOpen={addRouteModalOpen}
        onClose={() => setAddRouteModalOpen(false)}
        onAddRoute={addRouteFromModal}
        schools={schools}
        isAdding={addingRoute}
      />

      <DeleteConfirmModal
        isOpen={deleteModal.open}
        onClose={() => !deleting && setDeleteModal({ open: false, type: null, id: null, name: null })}
        onConfirm={handleConfirmDelete}
        title={
          deleteModal.type === "driver"
            ? "Remove driver"
            : deleteModal.type === "parent"
              ? "Remove parent"
              : deleteModal.type === "route"
                ? "Delete route"
                : deleteModal.type === "school"
                  ? "Delete school"
                  : "Delete"
        }
        description="This will move the record to Deleted Records. You can restore it later."
        itemName={deleteModal.name}
        confirmLabel="Soft delete"
        isLoading={deleting}
      />
    </div>
  );
};

export default AdminDashboard;
