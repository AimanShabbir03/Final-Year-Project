import React, { useEffect, useState } from "react";
import { db, auth } from "../firebase";
import {
  collection,
  onSnapshot,
  setDoc,
  doc,
  getDoc,
  query,
  where,
  updateDoc,
  serverTimestamp,
  deleteField,
  increment,
} from "firebase/firestore";
import { createUserWithEmailAndPassword, signOut } from "firebase/auth";
import DeleteConfirmModal from "../components/DeleteConfirmModal";
import { useToast } from "../contexts/ToastContext";
import LogsTab from "../components/LogsTab";
import DeletedRecordsTab from "../components/DeletedRecordsTab";
import AdminReportsTab from "../components/AdminReportsTab";
import { loadStripe } from "@stripe/stripe-js";
import { Elements, PaymentElement, useElements, useStripe } from "@stripe/react-stripe-js";

const stripePromise = loadStripe(
  process.env.REACT_APP_STRIPE_PUBLISHABLE_KEY ||
    "pk_test_51TlMHqPM88mauh5Tvwp3bKB73kb2e5LAg6Ke5hRXvKGIwnmnpfLQQKHrbHwEG2Jonq3JsHOSRp1YP1dne0FyuTXK00ybrjUneY",
);
const transportApiBaseUrl =
  process.env.REACT_APP_TRANSPORT_API_BASE_URL || "http://172.20.72.183:8000";

const resolveSalaryApiBaseUrls = () => {
  const fromEnv = String(
    process.env.REACT_APP_TRANSPORT_API_BASE_URL || "",
  ).trim();
  const fromDefault = String(transportApiBaseUrl || "").trim();
  const candidates = [
    fromEnv,
    fromDefault,
    "http://127.0.0.1:8000",
    "http://localhost:8000",
  ].filter(Boolean);
  return [...new Set(candidates)];
};

const SalaryStripePaymentForm = ({
  onCancel,
  onSuccess,
  setErrorMessage,
  setIsSubmitting,
}) => {
  const stripe = useStripe();
  const elements = useElements();

  const onPay = async () => {
    if (!stripe || !elements) return;
    setErrorMessage("");
    setIsSubmitting(true);
    try {
      const result = await stripe.confirmPayment({
        elements,
        confirmParams: {
          return_url: window.location.href,
        },
        redirect: "if_required",
      });

      if (result.error) {
        setErrorMessage(result.error.message || "Salary payment failed.");
        setIsSubmitting(false);
        return;
      }

      const intent = result.paymentIntent;
      if (!intent || intent.status !== "succeeded") {
        setErrorMessage("Salary payment was not completed.");
        setIsSubmitting(false);
        return;
      }

      await onSuccess(intent.id);
    } catch (e) {
      setErrorMessage(e.message || "Salary payment failed.");
      setIsSubmitting(false);
    }
  };

  return (
    <>
      <PaymentElement />
      <div className="flex justify-end gap-2 mt-4">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 rounded-lg bg-slate-100 text-slate-700 hover:bg-slate-200"
        >
          Cancel
        </button>
        <button
          type="button"
          onClick={onPay}
          disabled={!stripe || !elements}
          className="px-4 py-2 rounded-lg bg-violet-600 text-white hover:bg-violet-700 disabled:opacity-60"
        >
          Confirm Salary Payment
        </button>
      </div>
    </>
  );
};

const SuperAdminDashboard = () => {
  const { success, error } = useToast();
  const [activeTab, setActiveTab] = useState("dashboard");
  const [admins, setAdmins] = useState([]);
  const [deletedAdmins, setDeletedAdmins] = useState([]);
  const [userLabelsById, setUserLabelsById] = useState({});
  const [loading, setLoading] = useState(true);
  const [newAdminEmail, setNewAdminEmail] = useState("");
  const [newAdminPassword, setNewAdminPassword] = useState("");
  const [newAdminCity, setNewAdminCity] = useState("Abbottabad");
  const [adding, setAdding] = useState(false);
  const [collapsed, setCollapsed] = useState(false);
  const [deleteModal, setDeleteModal] = useState({ open: false, admin: null });
  const [viewAdminModal, setViewAdminModal] = useState({ open: false, admin: null });
  const [deleting, setDeleting] = useState(false);
  const [payments, setPayments] = useState([]);
  const [ledgerEntries, setLedgerEntries] = useState([]);
  const [adminSalaries, setAdminSalaries] = useState([]);
  const [payingSalaryFor, setPayingSalaryFor] = useState(null);
  const [currentUserRole, setCurrentUserRole] = useState("");
  const [currentUserProfile, setCurrentUserProfile] = useState({});
  const [totalDrivers, setTotalDrivers] = useState(0);
  const [totalParents, setTotalParents] = useState(0);
  const [totalRides, setTotalRides] = useState(0);
  const [transactions, setTransactions] = useState([]);
  const [commissionSettings, setCommissionSettings] = useState({
    driverSharePercent: 70,
    platformSharePercent: 30,
  });
  const [savingCommission, setSavingCommission] = useState(false);
  const [transactionFilters, setTransactionFilters] = useState({
    parentName: "",
    driverName: "",
    transactionId: "",
    paymentStatus: "all",
    date: "",
  });
  const [salaryPaymentDialog, setSalaryPaymentDialog] = useState({
    open: false,
    admin: null,
    clientSecret: "",
    paymentIntentId: "",
    salaryDocId: "",
    monthKey: "",
    amount: 40000,
  });
  const [salaryPaymentError, setSalaryPaymentError] = useState("");
  const [salaryPaymentSubmitting, setSalaryPaymentSubmitting] = useState(false);
  const [selectedPayrollMonthByAdmin, setSelectedPayrollMonthByAdmin] = useState({});

  useEffect(() => {
    setLoading(true);
    const adminsQuery = query(collection(db, "users"), where("role", "==", "admin"));
    const unsubAdmins = onSnapshot(
      adminsQuery,
      (snapshot) => {
        const allAdmins = snapshot.docs.map((d) => ({ id: d.id, ...d.data() }));
        setAdmins(allAdmins.filter((admin) => admin.isDeleted !== true));
        setDeletedAdmins(allAdmins.filter((admin) => admin.isDeleted === true));
        setLoading(false);
      },
      () => setLoading(false),
    );
    return () => unsubAdmins();
  }, []);

  useEffect(() => {
    const unsubUsers = onSnapshot(collection(db, "users"), (snapshot) => {
      const labels = {};
      let driversCount = 0;
      let parentsCount = 0;
      snapshot.docs.forEach((d) => {
        const data = d.data();
        labels[d.id] = String(data.name || data.email || "").trim();
        if (data.isDeleted === true) return;
        const role = String(data.role || "").toLowerCase();
        if (role === "driver") driversCount += 1;
        if (role === "parent") parentsCount += 1;
      });
      setUserLabelsById(labels);
      setTotalDrivers(driversCount);
      setTotalParents(parentsCount);
    });
    return () => unsubUsers();
  }, []);

  useEffect(() => {
    const unsubRides = onSnapshot(collection(db, "rides"), (snapshot) => {
      setTotalRides(snapshot.docs.length);
    });
    return () => unsubRides();
  }, []);


  // Collapse sidebar by default on mobile & tablet
  useEffect(() => {
    if (window.innerWidth < 1024) {
      setCollapsed(true);
    }
  }, []);

  useEffect(() => {
    const unsubPayments = onSnapshot(collection(db, "payments"), (snapshot) => {
      setPayments(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    const unsubLedger = onSnapshot(collection(db, "earnings_ledger"), (snapshot) => {
      setLedgerEntries(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    const unsubSalaries = onSnapshot(collection(db, "admin_salaries"), (snapshot) => {
      setAdminSalaries(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => {
      unsubPayments();
      unsubLedger();
      unsubSalaries();
    };
  }, []);

  useEffect(() => {
    const unsubTransactions = onSnapshot(collection(db, "transactions"), (snapshot) => {
      setTransactions(snapshot.docs.map((d) => ({ id: d.id, ...d.data() })));
    });
    return () => unsubTransactions();
  }, []);

  useEffect(() => {
    const settingsRef = doc(db, "system_settings", "commission_settings");
    const unsubSettings = onSnapshot(settingsRef, async (snap) => {
      if (!snap.exists()) {
        await setDoc(
          settingsRef,
          {
            driverSharePercent: 70,
            platformSharePercent: 30,
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        );
        return;
      }
      const row = snap.data() || {};
      setCommissionSettings({
        driverSharePercent: Number(row.driverSharePercent ?? 70),
        platformSharePercent: Number(row.platformSharePercent ?? 30),
      });
    });
    return () => unsubSettings();
  }, []);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (user) => {
      if (!user) {
        setCurrentUserRole("");
        setCurrentUserProfile({});
        return;
      }
      const me = await getDoc(doc(db, "users", user.uid));
      if (me.exists()) {
        const meData = me.data();
        setCurrentUserRole(String(meData.role || "").toLowerCase().trim());
        setCurrentUserProfile(meData);
      } else {
        setCurrentUserRole("");
        setCurrentUserProfile({});
      }
    });
    return () => unsubscribe();
  }, []);

  const handleAddAdmin = async () => {
    if (!newAdminEmail || !newAdminPassword) {
      error("Enter email and password.");
      return;
    }
    setAdding(true);
    try {
      const userCredential = await createUserWithEmailAndPassword(auth, newAdminEmail, newAdminPassword);
      const uid = userCredential.user.uid;
      await setDoc(doc(db, "users", uid), {
        email: newAdminEmail,
        name: newAdminEmail.split("@")[0],
        role: "admin",
        uid,
        city: newAdminCity,
        cityId: newAdminCity.toLowerCase(),
        isDeleted: false,
        status: "active",
        createdAt: new Date(),
      });
      setNewAdminEmail("");
      setNewAdminPassword("");
      setNewAdminCity("Abbottabad");
      success("Admin added successfully!");
    } catch (err) {
      error(err.code === "auth/email-already-in-use" ? "Email already registered." : err.message);
    } finally {
      setAdding(false);
    }
  };

  const handleRemoveAdminClick = (admin) => {
    setDeleteModal({ open: true, admin });
  };

  const handleConfirmDeleteAdmin = async () => {
    if (!deleteModal.admin) return;
    if (currentUserRole !== "superadmin") {
      error("Only super admin can remove admins.");
      return;
    }
    setDeleting(true);
    try {
      await updateDoc(doc(db, "users", deleteModal.admin.id), {
        isDeleted: true,
        deletedAt: serverTimestamp(),
        deletedBy: auth.currentUser?.uid || "",
        status: "inactive",
      });
      success("Admin moved to deleted admins.");
      setDeleteModal({ open: false, admin: null });
    } catch (err) {
      error("Failed to remove admin. Please try again.");
    } finally {
      setDeleting(false);
    }
  };

  const handleRestoreAdmin = async (admin) => {
    if (currentUserRole !== "superadmin") {
      error("Only super admin can restore admins.");
      return;
    }
    try {
      await updateDoc(doc(db, "users", admin.id), {
        isDeleted: false,
        deletedAt: deleteField(),
        deletedBy: deleteField(),
        status: "active",
      });
      success("Admin restored successfully.");
    } catch (err) {
      error("Failed to restore admin.");
    }
  };

  const handleLogout = async () => {
    await signOut(auth);
    window.location.href = "/login";
  };

  const currentMonthKey = new Date().toISOString().slice(0, 7);

  const parseMonthKey = (value) => {
    const parts = String(value || "").split("-");
    if (parts.length !== 2) return null;
    const year = Number(parts[0]);
    const month = Number(parts[1]);
    if (!Number.isFinite(year) || !Number.isFinite(month) || month < 1 || month > 12) {
      return null;
    }
    return new Date(year, month - 1, 1);
  };

  const formatMonthKeyLabel = (value) => {
    const dt = parseMonthKey(value);
    if (!dt) return String(value || "—");
    return dt.toLocaleString("en-US", { month: "long", year: "numeric" });
  };

  const toMonthKey = (value) => {
    const dt = value instanceof Date ? value : new Date(value);
    if (Number.isNaN(dt.getTime())) return "";
    return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}`;
  };

  const addMonths = (date, months) => new Date(date.getFullYear(), date.getMonth() + months, 1);

  const getAdminSalaryRecord = (adminId, monthKeyValue) =>
    adminSalaries.find((s) => s.adminId === adminId && s.monthKey === monthKeyValue);

  const sortMonthKeysDesc = (list) =>
    Array.from(new Set(list))
      .filter(Boolean)
      .sort((a, b) => {
        const aDate = parseMonthKey(a);
        const bDate = parseMonthKey(b);
        if (!aDate && !bDate) return 0;
        if (!aDate) return 1;
        if (!bDate) return -1;
        return bDate.getTime() - aDate.getTime();
      });

  const getAdminPayrollMonths = (adminId) => {
    const adminMonths = adminSalaries
      .filter((row) => row.adminId === adminId && row.monthKey)
      .map((row) => String(row.monthKey));
    adminMonths.push(currentMonthKey);
    return sortMonthKeysDesc(adminMonths);
  };

  useEffect(() => {
    if (!admins.length) return;
    setSelectedPayrollMonthByAdmin((prev) => {
      const next = { ...prev };
      let changed = false;
      admins.forEach((admin) => {
        const options = getAdminPayrollMonths(admin.id);
        const defaultMonth = options.includes(currentMonthKey)
          ? currentMonthKey
          : (options[0] || currentMonthKey);
        if (!next[admin.id] || !options.includes(next[admin.id])) {
          next[admin.id] = defaultMonth;
          changed = true;
        }
      });
      return changed ? next : prev;
    });
  }, [admins, adminSalaries, currentMonthKey]);

  useEffect(() => {
    if (!admins.length) return;
    const baseDate = parseMonthKey(currentMonthKey) || new Date();
    const autoMonths = [
      currentMonthKey,
      toMonthKey(addMonths(baseDate, 1)),
      toMonthKey(addMonths(baseDate, 2)),
    ].filter(Boolean);

    const existingKeys = new Set(
      adminSalaries
        .map((row) => `${row.adminId || ""}_${row.monthKey || ""}`)
        .filter((key) => key !== "_"),
    );

    const missingRecords = [];
    admins.forEach((admin) => {
      autoMonths.forEach((month) => {
        const key = `${admin.id}_${month}`;
        if (!existingKeys.has(key)) {
          missingRecords.push({
            id: key,
            adminId: admin.id,
            monthKey: month,
            salary: 40000,
            status: "pending",
          });
        }
      });
    });

    if (!missingRecords.length) return;

    Promise.all(
      missingRecords.map((row) =>
        setDoc(
          doc(db, "admin_salaries", row.id),
          {
            adminId: row.adminId,
            monthKey: row.monthKey,
            salary: row.salary,
            status: "pending",
            createdAt: serverTimestamp(),
            updatedAt: serverTimestamp(),
          },
          { merge: true },
        ),
      ),
    ).catch(() => {
      // Keep UI usable even if auto-create fails for some docs.
    });
  }, [admins, adminSalaries, currentMonthKey]);

  const paySalary = async (admin, salaryMonthKey = currentMonthKey) => {
    if (currentUserRole !== "superadmin") {
      error("Only super admin can pay salary.");
      return;
    }
    const salaryDocId = `${admin.id}_${salaryMonthKey}`;
    const existingRecord = getAdminSalaryRecord(admin.id, salaryMonthKey);
    if (String(existingRecord?.status || "").toLowerCase() === "paid") {
      error(`Salary for ${formatMonthKeyLabel(salaryMonthKey)} is already paid.`);
      return;
    }
    setPayingSalaryFor(salaryDocId);
    try {
      const salaryDocRef = doc(db, "admin_salaries", salaryDocId);
      const salaryDocSnap = await getDoc(salaryDocRef);
      if (salaryDocSnap.exists()) {
        const row = salaryDocSnap.data() || {};
        if (String(row.status || "").toLowerCase() === "paid") {
          throw new Error(`Salary for ${formatMonthKeyLabel(salaryMonthKey)} is already paid.`);
        }
      }

      const payload = {
        amount: 40000,
        adminId: admin.id,
        superAdminId: auth.currentUser?.uid || "",
        monthKey: salaryMonthKey,
      };
      const baseUrls = resolveSalaryApiBaseUrls();
      let data = null;
      let lastError = "";
      for (const baseUrl of baseUrls) {
        try {
          const response = await fetch(
            `${baseUrl}/create-admin-salary-payment-intent`,
            {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify(payload),
            },
          );
          if (!response.ok) {
            const text = await response.text();
            lastError = `(${response.status}) ${text}`;
            continue;
          }
          data = await response.json();
          if (data) break;
        } catch (networkError) {
          lastError = networkError?.message || "Network request failed.";
        }
      }
      if (!data) {
        throw new Error(
          `Failed to create salary payment intent. ${lastError || "Check API server on port 8000."}`,
        );
      }
      const clientSecret = String(data.client_secret || "").trim();
      const paymentIntentId = String(data.payment_intent_id || "").trim();
      if (!clientSecret || !paymentIntentId) {
        throw new Error("Missing salary payment intent response.");
      }
      setSalaryPaymentError("");
      setSalaryPaymentDialog({
        open: true,
        admin,
        clientSecret,
        paymentIntentId,
        salaryDocId,
        monthKey: salaryMonthKey,
        amount: 40000,
      });
    } catch (err) {
      error(err.message || "Failed to initialize salary payment.");
    } finally {
      setPayingSalaryFor(null);
    }
  };

  const saveCommissionSettings = async () => {
    const driver = Number(commissionSettings.driverSharePercent);
    const platform = Number(commissionSettings.platformSharePercent);
    if (
      !Number.isFinite(driver) ||
      !Number.isFinite(platform) ||
      driver < 0 ||
      driver > 100 ||
      platform < 0 ||
      platform > 100
    ) {
      error("Commission values must be between 0 and 100.");
      return;
    }
    if (Math.abs(driver + platform - 100) > 0.0001) {
      error("Driver and platform shares must total 100%.");
      return;
    }
    setSavingCommission(true);
    try {
      await setDoc(
        doc(db, "system_settings", "commission_settings"),
        {
          driverSharePercent: driver,
          platformSharePercent: platform,
          updatedAt: serverTimestamp(),
          updatedBy: auth.currentUser?.uid || "",
        },
        { merge: true },
      );
      success("Revenue & commission settings updated.");
    } catch (e) {
      error("Failed to save commission settings.");
    } finally {
      setSavingCommission(false);
    }
  };

  const handleSalaryStripeSuccess = async (confirmedPaymentIntentId) => {
    const { admin, salaryDocId, monthKey: salaryMonthKey, amount } = salaryPaymentDialog;
    if (!admin || !salaryDocId) {
      setSalaryPaymentError("Missing salary context for finalization.");
      setSalaryPaymentSubmitting(false);
      return;
    }

    try {
      const salaryDocRef = doc(db, "admin_salaries", salaryDocId);
      const salaryDocSnap = await getDoc(salaryDocRef);
      if (salaryDocSnap.exists()) {
        const existing = salaryDocSnap.data() || {};
        if (String(existing.status || "").toLowerCase() === "paid") {
          throw new Error(`Salary for ${formatMonthKeyLabel(salaryMonthKey)} is already paid.`);
        }
      }

      const paidAt = serverTimestamp();
      await setDoc(
        salaryDocRef,
        {
          adminId: admin.id,
          monthKey: salaryMonthKey,
          salary: amount,
          status: "paid",
          paidAt,
          lastPaidDate: paidAt,
          stripePaymentIntentId: confirmedPaymentIntentId,
          paymentMethod: "stripe",
          amountPaid: amount,
          paymentDateTime: paidAt,
        },
        { merge: true },
      );

      const transactionRef = doc(collection(db, "transactions"));
      const transactionId = transactionRef.id;
      await setDoc(
        transactionRef,
        {
          transactionId,
          type: "payroll_salary",
          stripePaymentIntentId: confirmedPaymentIntentId,
          parentId: "",
          driverId: "",
          adminId: admin.id,
          rideId: "",
          amount: amount,
          driverShare: 0,
          adminCommission: 0,
          paymentStatus: "paid",
          paymentMethod: "stripe",
          salaryDocId,
          salaryMonthKey,
          dateTime: serverTimestamp(),
          createdAt: serverTimestamp(),
          updatedAt: serverTimestamp(),
          notes: `Salary paid to admin ${admin.id} for ${salaryMonthKey}`,
        },
        { merge: true },
      );

      const adminAccountId = `admin_${admin.id}`;
      const superAdminUid = auth.currentUser?.uid || "platform";
      const superAdminAccountId = `superadmin_${superAdminUid}`;
      await setDoc(
        doc(db, "financial_accounts", adminAccountId),
        {
          accountId: adminAccountId,
          userId: admin.id,
          role: "admin",
          updatedAt: serverTimestamp(),
          createdAt: serverTimestamp(),
          totalSalaryReceived: increment(Number(amount || 0)),
          totalTransactions: increment(1),
        },
        { merge: true },
      );
      await setDoc(
        doc(db, "financial_accounts", superAdminAccountId),
        {
          accountId: superAdminAccountId,
          userId: superAdminUid,
          role: "superadmin",
          updatedAt: serverTimestamp(),
          createdAt: serverTimestamp(),
          totalPayrollPaid: increment(Number(amount || 0)),
          totalTransactions: increment(1),
        },
        { merge: true },
      );

      await setDoc(
        salaryDocRef,
        {
          transactionId,
          updatedAt: serverTimestamp(),
        },
        { merge: true },
      );
      setAdminSalaries((prev) => {
        const next = [...prev];
        const idx = next.findIndex((row) => row.id === salaryDocId);
        const merged = {
          id: salaryDocId,
          adminId: admin.id,
          monthKey: salaryMonthKey,
          salary: amount,
          status: "paid",
          transactionId,
          stripePaymentIntentId: confirmedPaymentIntentId,
          amountPaid: amount,
          paymentMethod: "stripe",
          paidAt: new Date(),
          lastPaidDate: new Date(),
          paymentDateTime: new Date(),
        };
        if (idx >= 0) {
          next[idx] = { ...next[idx], ...merged };
        } else {
          next.push(merged);
        }
        return next;
      });
      success("Salary payment completed via Stripe.");
      setSalaryPaymentDialog({
        open: false,
        admin: null,
        clientSecret: "",
        paymentIntentId: "",
        salaryDocId: "",
        monthKey: "",
        amount: 40000,
      });
      setSalaryPaymentError("");
      setSalaryPaymentSubmitting(false);
    } catch (e) {
      setSalaryPaymentError(e.message || "Failed to finalize salary payment.");
      setSalaryPaymentSubmitting(false);
    }
  };

  const paidPaymentsCount = payments.filter((p) => p.status === "paid").length;
  const pendingPaymentsCount = payments.filter((p) => p.status !== "paid").length;
  const superAdminTotal = ledgerEntries.reduce(
    (sum, entry) => sum + Number(entry.superAdminAmount || 0),
    0,
  );
  const successfulStripeTransactions = transactions.filter((tx) => {
    const method = String(tx.paymentMethod || "").toLowerCase();
    const status = String(tx.paymentStatus || "").toLowerCase();
    return method.includes("stripe") && status === "paid";
  });
  const getTransactionTypeLabel = (tx) => {
    const type = String(tx.type || tx.transactionType || "")
      .toLowerCase()
      .trim();
    if (type.includes("salary") || type === "payroll_salary") {
      return "Salary Payment";
    }
    return "Ride Payment";
  };
  const ridePaymentTransactions = successfulStripeTransactions.filter(
    (tx) => getTransactionTypeLabel(tx) === "Ride Payment",
  );
  const salaryPaymentTransactions = successfulStripeTransactions.filter(
    (tx) => getTransactionTypeLabel(tx) === "Salary Payment",
  );
  const totalRevenue = ridePaymentTransactions.reduce(
    (sum, tx) => sum + Number(tx.amount || 0),
    0,
  );
  const totalDriverEarnings = ridePaymentTransactions.reduce(
    (sum, tx) => sum + Number(tx.driverShare || 0),
    0,
  );
  const totalPlatformShare = ridePaymentTransactions.reduce(
    (sum, tx) => sum + Number(tx.adminCommission || 0),
    0,
  );
  const totalSalaryPaid = salaryPaymentTransactions.reduce(
    (sum, tx) => sum + Number(tx.amount || 0),
    0,
  );
  const totalTransactionCount = successfulStripeTransactions.length;

  const getTimestampDate = (value) => {
    if (value?.toDate) return value.toDate();
    if (value instanceof Date) return value;
    if (typeof value === "string" || typeof value === "number") {
      const parsed = new Date(value);
      if (!Number.isNaN(parsed.getTime())) return parsed;
    }
    return null;
  };
  const formatDateTime = (value) => {
    const dt = getTimestampDate(value);
    if (!dt) return "—";
    return dt.toLocaleString();
  };
  const formatPaymentMethod = (method) => {
    const normalized = String(method || "").toLowerCase();
    if (normalized.includes("stripe")) return "Stripe";
    return normalized || "—";
  };
  const filteredTransactions = successfulStripeTransactions.filter((tx) => {
    const parentName =
      String(userLabelsById[tx.parentId] || tx.parentId || "").toLowerCase();
    const driverName =
      String(userLabelsById[tx.driverId] || tx.driverId || "").toLowerCase();
    const transactionId = String(tx.transactionId || "").toLowerCase();
    const status = String(tx.paymentStatus || "").toLowerCase();
    if (
      transactionFilters.parentName &&
      !parentName.includes(transactionFilters.parentName.toLowerCase())
    ) {
      return false;
    }
    if (
      transactionFilters.driverName &&
      !driverName.includes(transactionFilters.driverName.toLowerCase())
    ) {
      return false;
    }
    if (
      transactionFilters.transactionId &&
      !transactionId.includes(transactionFilters.transactionId.toLowerCase())
    ) {
      return false;
    }
    if (
      transactionFilters.paymentStatus !== "all" &&
      status !== transactionFilters.paymentStatus
    ) {
      return false;
    }
    if (transactionFilters.date) {
      const dt = getTimestampDate(tx.dateTime || tx.createdAt);
      if (!dt) return false;
      const day = `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(
        2,
        "0",
      )}-${String(dt.getDate()).padStart(2, "0")}`;
      if (day !== transactionFilters.date) return false;
    }
    return true;
  });
  const formatCreatedAt = (value) => {
    if (value?.toDate) return value.toDate().toLocaleDateString();
    if (value instanceof Date) return value.toLocaleDateString();
    if (typeof value === "string" || typeof value === "number") {
      const dt = new Date(value);
      if (!Number.isNaN(dt.getTime())) return dt.toLocaleDateString();
    }
    return "Not provided";
  };
  const getStatusLabel = (admin) => {
    if (admin?.isDeleted === true) return "Deleted";
    const normalized = String(admin?.status || "").trim().toLowerCase();
    if (!normalized) return "Active";
    if (normalized === "active") return "Active";
    if (normalized === "inactive") return "Suspended";
    return normalized.charAt(0).toUpperCase() + normalized.slice(1);
  };
  const getAdminProfileImage = (admin) =>
    String(admin?.profileImageUrl || admin?.profilePic || "").trim();
  const getAdminName = (admin) =>
    String(admin?.name || admin?.fullName || admin?.displayName || "").trim() || "Not provided";
  const getAdminEmail = (admin) =>
    String(admin?.email || "").trim() || "Not provided";
  const getAdminIdentifier = (admin) => {
    const email = String(admin?.email || "").trim();
    if (email) return email;
    const username = String(admin?.username || admin?.userName || admin?.name || "").trim();
    if (username) return username;
    return String(admin?.id || "").trim() || "Not provided";
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gradient-to-br from-violet-50 via-purple-50 to-fuchsia-100">
        <div className="text-center">
          <div className="w-16 h-16 border-4 border-purple-200 border-t-purple-600 rounded-full animate-spin mx-auto mb-4"></div>
          <p className="text-purple-600 font-semibold">Loading...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col md:flex-row min-h-screen bg-gradient-to-br from-violet-50 via-purple-50 to-fuchsia-100">
      
      {/* ---------------- SIDEBAR ---------------- */}
      <div className={`${collapsed ? "w-full md:w-20" : "w-full md:w-72"} bg-gradient-to-b from-violet-600 via-purple-600 to-fuchsia-600 shadow-2xl transition-all duration-300 relative flex-shrink-0`}>
        <div className="p-6">
          {/* Header */}
          <div className="flex items-center justify-between mb-10">
            {!collapsed && (
              <div className="flex items-center gap-3">
                <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white font-bold text-xl shadow-lg">
                  <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                  </svg>
                </div>
                <div>
                  <h2 className="text-2xl font-bold text-white">SuperAdmin</h2>
                  <p className="text-xs text-purple-200">Master Control</p>
                </div>
              </div>
            )}
            {collapsed && (
              <div className="flex items-center gap-3 -mb-10 md:hidden">
              <div className="w-12 h-12 bg-white/20 backdrop-blur-sm rounded-xl flex items-center justify-center text-white font-bold text-xl shadow-lg">
                <svg className="w-7 h-7" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" />
                </svg>
              </div>
              <div>
                <h2 className="text-2xl font-bold text-white">SuperAdmin</h2>
                <p className="text-xs text-purple-200">Master Control</p>
              </div>
            </div>
            )}
          </div>

          <button 
            onClick={() => setCollapsed(!collapsed)}
            className="absolute top-6 right-4 w-8 h-8 bg-white/10 hover:bg-white/20 backdrop-blur-sm rounded-lg flex items-center justify-center text-white transition-all duration-300 hover:scale-110"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>

          {/* Navigation */}
          <nav className={`space-y-2 mt-8 ${collapsed ? "hidden" : ""}`}>
            <button
              onClick={() => setActiveTab("dashboard")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "dashboard" 
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105" 
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 5a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1H5a1 1 0 01-1-1V5zM14 5a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 16a1 1 0 011-1h4a1 1 0 011 1v3a1 1 0 01-1 1H5a1 1 0 01-1-1v-3zM14 12a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1v-7z" />
              </svg>
              {!collapsed && <span>Dashboard</span>}
            </button>

            <button
              onClick={() => setActiveTab("manageAdmins")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "manageAdmins" 
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105" 
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
              </svg>
              {!collapsed && <span>Manage Admins</span>}
            </button>

            <button
              onClick={() => setActiveTab("payments")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "payments" 
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105" 
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
              </svg>
              {!collapsed && <span>Payments</span>}
            </button>

            <button
              onClick={() => setActiveTab("payroll")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "payroll"
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105"
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8V7m0 1v8m0 0v1m0-1H9m3 0h3" />
              </svg>
              {!collapsed && <span>Payroll / Admin Salaries</span>}
            </button>

            <button
              onClick={() => setActiveTab("logs")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "logs"
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105"
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 12h6m-6 4h6M7 4h10a2 2 0 012 2v12a2 2 0 01-2 2H7a2 2 0 01-2-2V6a2 2 0 012-2z" />
              </svg>
              {!collapsed && <span>Logs</span>}
            </button>

            <button
              onClick={() => setActiveTab("deleted_records")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "deleted_records"
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105"
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 13h6m-7 4h8M7 7h10l-1 12H8L7 7zm3-3h4l1 2H9l1-2z" />
              </svg>
              {!collapsed && <span>Deleted Records</span>}
            </button>

            <button
              onClick={() => setActiveTab("admin_reports")}
              className={`w-full text-left px-4 py-3.5 rounded-xl transition-all duration-300 flex items-center gap-3 ${
                activeTab === "admin_reports"
                  ? "bg-white text-purple-600 shadow-lg font-semibold transform scale-105"
                  : "text-white hover:bg-white/10 hover:translate-x-1"
              }`}
            >
              <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 17v-6m4 6V7m4 10v-3M5 20h14a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
              </svg>
              {!collapsed && <span>Admin Reports</span>}
            </button>

            <div className="pt-4 mt-4 border-t border-white/20">
              <button
                onClick={handleLogout}
                className="w-full text-left px-4 py-3.5 rounded-xl text-white hover:bg-red-500/20 transition-all duration-300 flex items-center gap-3 hover:translate-x-1"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
                </svg>
                {!collapsed && <span>Logout</span>}
              </button>
            </div>
          </nav>
        </div>
      </div>

      {/* ---------------- MAIN CONTENT ---------------- */}
      <div className="flex-1 w-full p-4 md:p-8 overflow-auto">

        {/* ---------------- DASHBOARD ---------------- */}
        {activeTab === "dashboard" && (
          <div className="space-y-8">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-fuchsia-600 bg-clip-text text-transparent">Dashboard Overview</h2>
                <p className="text-gray-600 mt-1">Monitor your system at a glance</p>
              </div>
              <div className="text-sm text-gray-500">
                {new Date().toLocaleDateString('en-US', { weekday: 'long', year: 'numeric', month: 'long', day: 'numeric' })}
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
              {[
                { label: "Total Admins", value: admins.length, tone: "from-violet-500 to-purple-600" },
                { label: "Total Drivers", value: totalDrivers, tone: "from-cyan-500 to-blue-600" },
                { label: "Total Parents", value: totalParents, tone: "from-emerald-500 to-teal-600" },
                { label: "Total Rides", value: totalRides, tone: "from-fuchsia-500 to-pink-600" },
              ].map((card) => (
                <div key={card.label} className={`bg-gradient-to-r ${card.tone} p-6 rounded-2xl shadow-xl text-white`}>
                  <p className="text-sm text-white/90">{card.label}</p>
                  <p className="text-4xl font-bold mt-2">{card.value}</p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* ---------------- MANAGE ADMINS ---------------- */}
        {activeTab === "manageAdmins" && (
          <div className="space-y-6">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-purple-600 bg-clip-text text-transparent">Manage Admins</h2>
                <p className="text-gray-600 mt-1">Add and manage administrator accounts</p>
              </div>
              <div className="bg-white px-4 py-2 rounded-xl shadow-md">
                <span className="text-sm text-gray-600">Total: </span>
                <span className="font-bold text-purple-600 text-lg">{admins.length}</span>
              </div>
            </div>

            {/* Add Admin Form */}
            <div className="bg-white/80 backdrop-blur-lg p-6 rounded-2xl shadow-xl border border-white/20">
              <h3 className="text-xl font-semibold text-gray-800 mb-4 flex items-center gap-2">
                <svg className="w-6 h-6 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
                </svg>
                Add New Admin
              </h3>
              <div className="flex flex-col md:flex-row gap-4">
                <div className="flex-1">
                  <input
                    type="email"
                    placeholder="Admin email"
                    value={newAdminEmail}
                    onChange={(e) => setNewAdminEmail(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-400 focus:border-transparent shadow-sm transition bg-white"
                  />
                </div>
                <div className="flex-1">
                  <input
                    type="password"
                    placeholder="Admin password"
                    value={newAdminPassword}
                    onChange={(e) => setNewAdminPassword(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-400 focus:border-transparent shadow-sm transition bg-white"
                  />
                </div>
                <div className="flex-1">
                  <select
                    value={newAdminCity}
                    onChange={(e) => setNewAdminCity(e.target.value)}
                    className="w-full px-4 py-3 border border-gray-300 rounded-xl focus:outline-none focus:ring-2 focus:ring-purple-400 focus:border-transparent shadow-sm transition bg-white"
                  >
                    <option value="Abbottabad">Abbottabad</option>
                    <option value="Mansehra">Mansehra</option>
                    <option value="Rawalpindi">Rawalpindi</option>
                  </select>
                </div>
                <button
                  onClick={handleAddAdmin}
                  disabled={adding}
                  className={`px-6 py-3 rounded-xl text-white font-semibold transition-all duration-300 shadow-lg ${
                    adding 
                      ? "bg-gray-400 cursor-not-allowed" 
                      : "bg-gradient-to-r from-violet-500 to-purple-600 hover:from-violet-600 hover:to-purple-700 hover:shadow-xl transform hover:-translate-y-0.5"
                  }`}
                >
                  {adding ? (
                    <span className="flex items-center gap-2">
                      <svg className="animate-spin h-5 w-5" viewBox="0 0 24 24">
                        <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" fill="none"></circle>
                        <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                      </svg>
                      Adding...
                    </span>
                  ) : (
                    "Add Admin"
                  )}
                </button>
              </div>
            </div>

            {/* Admins Table */}
            <div className="bg-white shadow-2xl rounded-2xl border border-gray-100 overflow-x-auto">
              <table className="w-full min-w-[1100px]">
                <thead className="bg-gradient-to-r from-violet-600 to-purple-600 text-white">
                  <tr>
                    <th className="py-4 px-6 text-left font-semibold">Profile</th>
                    <th className="py-4 px-6 text-left font-semibold">Full Name</th>
                    <th className="py-4 px-6 text-left font-semibold">Email</th>
                    <th className="py-4 px-6 text-left font-semibold">Role</th>
                    <th className="py-4 px-6 text-left font-semibold">City</th>
                    <th className="py-4 px-6 text-left font-semibold">Status</th>
                    <th className="py-4 px-6 text-left font-semibold">Created At</th>
                    <th className="py-4 px-6 text-left font-semibold">Action</th>
                  </tr>
                </thead>

                <tbody>
                  {admins.map((admin, index) => (
                    <tr key={admin.id} className={`border-b transition-colors hover:bg-purple-50 ${index % 2 === 0 ? 'bg-gray-50' : 'bg-white'}`}>
                      <td className="py-4 px-6">
                        <div className="w-12 h-12 rounded-full overflow-hidden border border-violet-200 bg-violet-100 flex items-center justify-center text-violet-700 font-semibold">
                          {getAdminProfileImage(admin).length > 0 ? (
                            <img
                              src={getAdminProfileImage(admin)}
                              alt={getAdminName(admin)}
                              className="w-full h-full object-cover"
                            />
                          ) : (
                            <span>{getAdminEmail(admin).charAt(0).toUpperCase() || "A"}</span>
                          )}
                        </div>
                      </td>
                      <td className="py-4 px-6">
                        <span className="font-medium text-gray-800">{getAdminName(admin)}</span>
                      </td>
                      <td className="py-4 px-6">
                        <span className="font-medium text-gray-800">{getAdminEmail(admin)}</span>
                      </td>
                      <td className="py-4 px-6">
                        <span className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-purple-100 text-purple-700 rounded-full text-sm font-semibold">
                          <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                            <path fillRule="evenodd" d="M2.166 4.999A11.954 11.954 0 0010 1.944 11.954 11.954 0 0017.834 5c.11.65.166 1.32.166 2.001 0 5.225-3.34 9.67-8 11.317C5.34 16.67 2 12.225 2 7c0-.682.057-1.35.166-2.001zm11.541 3.708a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                          </svg>
                          {admin.role}
                        </span>
                      </td>
                      <td className="py-4 px-6 text-gray-700">
                        {String(admin.city || "Not provided")}
                      </td>
                      <td className="py-4 px-6">
                        <span className={`inline-flex px-3 py-1 rounded-full text-xs font-semibold ${
                          getStatusLabel(admin) === "Active"
                            ? "bg-emerald-100 text-emerald-700"
                            : getStatusLabel(admin) === "Deleted"
                              ? "bg-rose-100 text-rose-700"
                              : "bg-amber-100 text-amber-700"
                        }`}>
                          {getStatusLabel(admin)}
                        </span>
                      </td>
                      <td className="py-4 px-6 text-gray-700">
                        {formatCreatedAt(admin.createdAt)}
                      </td>
                      <td className="py-4 px-6">
                        <div className="flex items-center gap-2">
                          <button
                            onClick={() => setViewAdminModal({ open: true, admin })}
                            className="inline-flex items-center gap-1.5 bg-white border border-violet-300 text-violet-700 px-4 py-2 rounded-lg hover:bg-violet-50 transition-all duration-300 font-medium"
                          >
                            View Admin
                          </button>
                          <button
                            onClick={() => handleRemoveAdminClick(admin)}
                            className="inline-flex items-center gap-1.5 bg-gradient-to-r from-red-500 to-rose-600 text-white px-4 py-2 rounded-lg hover:from-red-600 hover:to-rose-700 transition-all duration-300 shadow-md hover:shadow-lg transform hover:-translate-y-0.5 font-medium"
                          >
                            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                            </svg>
                            Remove
                          </button>
                        </div>
                      </td>
                    </tr>
                  ))}
                  {admins.length === 0 && (
                    <tr>
                      <td colSpan="8" className="text-center py-12 text-gray-500">
                        <svg className="w-16 h-16 mx-auto mb-4 text-gray-300" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197M13 7a4 4 0 11-8 0 4 4 0 018 0z" />
                        </svg>
                        <p className="text-lg font-medium">No admins found</p>
                        <p className="text-sm text-gray-400 mt-1">Add your first admin above</p>
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>

            <div className="bg-white/80 backdrop-blur-lg p-6 rounded-2xl shadow-xl border border-white/20">
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-xl font-semibold text-gray-800">Deleted Admins</h3>
                <span className="text-sm text-gray-500">{deletedAdmins.length}</span>
              </div>

              {deletedAdmins.length === 0 ? (
                <p className="text-sm text-gray-500">No deleted admins.</p>
              ) : (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
                  {deletedAdmins.map((admin) => {
                    const deletedByName =
                      userLabelsById[admin.deletedBy] ||
                      currentUserProfile?.name ||
                      "Super Admin";
                    const deletedAtText = admin.deletedAt?.toDate
                      ? admin.deletedAt.toDate().toLocaleString()
                      : "—";
                    return (
                      <div
                        key={admin.id}
                        className="rounded-xl border border-gray-200 bg-white p-4 shadow-sm"
                      >
                        <p className="text-gray-800 font-semibold">
                          {admin.name || admin.email || "Admin"}
                        </p>
                        <p className="text-sm text-gray-600 mt-1">
                          Role: {(admin.role || "admin").toString()}
                        </p>
                        <p className="text-sm text-gray-600">
                          Deleted By: {deletedByName}
                        </p>
                        <p className="text-sm text-gray-600">
                          Date: {deletedAtText}
                        </p>
                        <div className="mt-3">
                          <button
                            onClick={() => handleRestoreAdmin(admin)}
                            disabled={currentUserRole !== "superadmin"}
                            className="px-4 py-2 rounded-lg bg-emerald-600 text-white hover:bg-emerald-700 disabled:opacity-50"
                          >
                            Restore
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        )}

        {/* ---------------- PAYMENTS ---------------- */}
        {activeTab === "payments" && (
          <div className="space-y-6">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-fuchsia-600 bg-clip-text text-transparent">Payments</h2>
                <p className="text-gray-600 mt-1">Manage payment transactions</p>
              </div>
            </div>

            <div className="bg-white/80 backdrop-blur-lg p-12 rounded-2xl shadow-xl border border-white/20 text-center">
              <div className="w-20 h-20 bg-gradient-to-br from-violet-100 to-purple-100 rounded-full flex items-center justify-center mx-auto mb-4">
                <svg className="w-10 h-10 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 10h18M7 15h1m4 0h1m-7 4h12a3 3 0 003-3V8a3 3 0 00-3-3H6a3 3 0 00-3 3v8a3 3 0 003 3z" />
                </svg>
              </div>
              <h3 className="text-xl font-semibold text-gray-800 mb-2">Payment System</h3>
              <div className="space-y-2 text-gray-700">
                <p>Paid payments: {paidPaymentsCount}</p>
                <p>Pending payments: {pendingPaymentsCount}</p>
                <p>Super Admin earnings (30%): PKR {superAdminTotal.toFixed(2)}</p>
              </div>
            </div>

            <div className="bg-white shadow-2xl rounded-2xl border border-gray-100 p-6">
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Revenue & Commission Settings</h3>
              <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
                <div>
                  <label className="block text-sm text-gray-600 mb-1">Driver Share (%)</label>
                  <input
                    type="number"
                    min="0"
                    max="100"
                    value={commissionSettings.driverSharePercent}
                    onChange={(e) =>
                      setCommissionSettings((prev) => ({
                        ...prev,
                        driverSharePercent: Number(e.target.value),
                      }))
                    }
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
                <div>
                  <label className="block text-sm text-gray-600 mb-1">Platform / Super Admin Share (%)</label>
                  <input
                    type="number"
                    min="0"
                    max="100"
                    value={commissionSettings.platformSharePercent}
                    onChange={(e) =>
                      setCommissionSettings((prev) => ({
                        ...prev,
                        platformSharePercent: Number(e.target.value),
                      }))
                    }
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
                <div className="flex items-end">
                  <button
                    onClick={saveCommissionSettings}
                    disabled={savingCommission}
                    className="w-full px-4 py-2 rounded-lg bg-violet-600 text-white hover:bg-violet-700 disabled:opacity-60"
                  >
                    {savingCommission ? "Saving..." : "Save Settings"}
                  </button>
                </div>
              </div>
              <p className="text-xs text-gray-500 mt-3">
                Driver + Platform shares must always equal 100%.
              </p>
            </div>

            <div className="bg-white shadow-2xl rounded-2xl border border-gray-100 p-6">
              <h3 className="text-xl font-semibold text-gray-800 mb-4">Financial Transaction Ledger</h3>
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-3 mb-4">
                <input
                  value={transactionFilters.parentName}
                  onChange={(e) =>
                    setTransactionFilters((prev) => ({
                      ...prev,
                      parentName: e.target.value,
                    }))
                  }
                  placeholder="Filter parent name"
                  className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
                />
                <input
                  value={transactionFilters.driverName}
                  onChange={(e) =>
                    setTransactionFilters((prev) => ({
                      ...prev,
                      driverName: e.target.value,
                    }))
                  }
                  placeholder="Filter driver name"
                  className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
                />
                <input
                  value={transactionFilters.transactionId}
                  onChange={(e) =>
                    setTransactionFilters((prev) => ({
                      ...prev,
                      transactionId: e.target.value,
                    }))
                  }
                  placeholder="Filter transaction ID"
                  className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
                />
                <select
                  value={transactionFilters.paymentStatus}
                  onChange={(e) =>
                    setTransactionFilters((prev) => ({
                      ...prev,
                      paymentStatus: e.target.value,
                    }))
                  }
                  className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
                >
                  <option value="all">All statuses</option>
                  <option value="paid">Paid</option>
                  <option value="pending">Pending</option>
                  <option value="failed">Failed</option>
                </select>
                <input
                  type="date"
                  value={transactionFilters.date}
                  onChange={(e) =>
                    setTransactionFilters((prev) => ({
                      ...prev,
                      date: e.target.value,
                    }))
                  }
                  className="px-3 py-2 border border-gray-300 rounded-lg text-sm"
                />
              </div>

              <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-5 gap-3 mb-4">
                <div className="rounded-lg bg-violet-50 border border-violet-100 p-3">
                  <p className="text-xs text-violet-700">Total Revenue</p>
                  <p className="text-lg font-bold text-violet-800">
                    PKR {totalRevenue.toFixed(2)}
                  </p>
                </div>
                <div className="rounded-lg bg-emerald-50 border border-emerald-100 p-3">
                  <p className="text-xs text-emerald-700">Total Driver Earnings</p>
                  <p className="text-lg font-bold text-emerald-800">
                    PKR {totalDriverEarnings.toFixed(2)}
                  </p>
                </div>
                <div className="rounded-lg bg-fuchsia-50 border border-fuchsia-100 p-3">
                  <p className="text-xs text-fuchsia-700">Platform / Super Admin Share</p>
                  <p className="text-lg font-bold text-fuchsia-800">
                    PKR {totalPlatformShare.toFixed(2)}
                  </p>
                </div>
                <div className="rounded-lg bg-amber-50 border border-amber-100 p-3">
                  <p className="text-xs text-amber-700">Total Salary Paid</p>
                  <p className="text-lg font-bold text-amber-800">
                    PKR {totalSalaryPaid.toFixed(2)}
                  </p>
                </div>
                <div className="rounded-lg bg-slate-50 border border-slate-200 p-3">
                  <p className="text-xs text-slate-700">Total Transactions</p>
                  <p className="text-lg font-bold text-slate-800">
                    {totalTransactionCount}
                  </p>
                </div>
              </div>

              <div className="overflow-x-auto rounded-xl border border-gray-200">
                <table className="min-w-[1650px] w-full text-sm border-collapse">
                  <thead>
                    <tr className="bg-gray-50">
                      <th className="px-3 py-2 border border-gray-200 text-left">Transaction Type</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Transaction ID</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Stripe PaymentIntent ID</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Parent Name</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Driver Name</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Ride ID</th>
                      <th className="px-3 py-2 border border-gray-200 text-right">Amount</th>
                      <th className="px-3 py-2 border border-gray-200 text-right">Driver Share Amount</th>
                      <th className="px-3 py-2 border border-gray-200 text-right">Platform / Super Admin Share Amount</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Payment Status</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Payment Date & Time</th>
                      <th className="px-3 py-2 border border-gray-200 text-left">Payment Method</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredTransactions.map((tx) => {
                      const transactionType = getTransactionTypeLabel(tx);
                      const isSalaryPayment = transactionType === "Salary Payment";
                      return (
                      <tr key={tx.id} className="border-b border-gray-100">
                        <td className="px-3 py-2 border border-gray-200">{transactionType}</td>
                        <td className="px-3 py-2 border border-gray-200">{tx.transactionId || "—"}</td>
                        <td className="px-3 py-2 border border-gray-200">{tx.stripePaymentIntentId || "—"}</td>
                        <td className="px-3 py-2 border border-gray-200">
                          {userLabelsById[tx.parentId] || tx.parentId || "—"}
                        </td>
                        <td className="px-3 py-2 border border-gray-200">
                          {userLabelsById[tx.driverId] || tx.driverId || "—"}
                        </td>
                        <td className="px-3 py-2 border border-gray-200">{tx.rideId || "—"}</td>
                        <td className="px-3 py-2 border border-gray-200 text-right">
                          {Number(tx.amount || 0).toFixed(2)}
                        </td>
                        <td className="px-3 py-2 border border-gray-200 text-right">
                          {isSalaryPayment ? "—" : Number(tx.driverShare || 0).toFixed(2)}
                        </td>
                        <td className="px-3 py-2 border border-gray-200 text-right">
                          {isSalaryPayment ? "—" : Number(tx.adminCommission || 0).toFixed(2)}
                        </td>
                        <td className="px-3 py-2 border border-gray-200">{tx.paymentStatus || "—"}</td>
                        <td className="px-3 py-2 border border-gray-200">
                          {formatDateTime(tx.dateTime || tx.createdAt)}
                        </td>
                        <td className="px-3 py-2 border border-gray-200">
                          {formatPaymentMethod(tx.paymentMethod)}
                        </td>
                      </tr>
                    );
                    })}
                    {filteredTransactions.length === 0 && (
                      <tr>
                        <td
                          colSpan={12}
                          className="px-3 py-3 border border-gray-200 text-center text-gray-500"
                        >
                          No transaction records found.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          </div>
        )}

        {/* ---------------- PAYROLL ---------------- */}
        {activeTab === "payroll" && (
          <div className="space-y-6">
            <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
              <div>
                <h2 className="text-4xl font-bold bg-gradient-to-r from-violet-600 to-fuchsia-600 bg-clip-text text-transparent">
                  Payroll / Admin Salaries
                </h2>
                <p className="text-gray-600 mt-1">Manage monthly admin salaries</p>
              </div>
            </div>

            <div className="bg-white shadow-2xl rounded-2xl border border-gray-100 overflow-x-auto">
              <table className="w-full min-w-[900px]">
                <thead className="bg-gradient-to-r from-violet-600 to-purple-600 text-white">
                  <tr>
                    <th className="py-4 px-6 text-left font-semibold">Admin Name</th>
                    <th className="py-4 px-6 text-left font-semibold">Admin Account</th>
                    <th className="py-4 px-6 text-left font-semibold">Monthly Earnings</th>
                    <th className="py-4 px-6 text-left font-semibold">Month</th>
                    <th className="py-4 px-6 text-left font-semibold">Salary Status</th>
                    <th className="py-4 px-6 text-left font-semibold">Last Paid Date</th>
                    <th className="py-4 px-6 text-left font-semibold">Transaction ID</th>
                    <th className="py-4 px-6 text-left font-semibold">Stripe PaymentIntent ID</th>
                    <th className="py-4 px-6 text-left font-semibold">Action</th>
                  </tr>
                </thead>
                <tbody>
                  {admins.map((admin, index) => {
                    const monthOptions = getAdminPayrollMonths(admin.id);
                    const selectedMonth =
                      selectedPayrollMonthByAdmin[admin.id] || currentMonthKey;
                    const monthKey = monthOptions.includes(selectedMonth)
                      ? selectedMonth
                      : (monthOptions[0] || currentMonthKey);
                    const salaryRecord = getAdminSalaryRecord(admin.id, monthKey);
                    const status = String(salaryRecord?.status || "pending").toLowerCase();
                    const paidDateSource =
                      salaryRecord?.lastPaidDate ||
                      salaryRecord?.paymentDateTime ||
                      salaryRecord?.paidAt;
                    const paidDate = formatDateTime(paidDateSource);
                    const transactionId = salaryRecord?.transactionId || "—";
                    const stripePaymentIntentId =
                      salaryRecord?.stripePaymentIntentId || "—";
                    const isPaid = status === "paid";
                    const rowPaying = payingSalaryFor === `${admin.id}_${monthKey}`;
                    return (
                      <tr key={admin.id} className={`border-b ${index % 2 === 0 ? "bg-gray-50" : "bg-white"}`}>
                        <td className="py-4 px-6">{admin.name || admin.email || "—"}</td>
                        <td className="py-4 px-6 text-sm text-gray-600">{getAdminIdentifier(admin)}</td>
                        <td className="py-4 px-6">PKR 40,000</td>
                        <td className="py-4 px-6">
                          <select
                            value={monthKey}
                            onChange={(e) =>
                              setSelectedPayrollMonthByAdmin((prev) => ({
                                ...prev,
                                [admin.id]: e.target.value,
                              }))
                            }
                            className="px-3 py-2 border border-gray-300 rounded-lg bg-white text-sm min-w-[170px]"
                          >
                            {monthOptions.map((optionMonth) => (
                              <option key={optionMonth} value={optionMonth}>
                                {formatMonthKeyLabel(optionMonth)}
                              </option>
                            ))}
                          </select>
                        </td>
                        <td className="py-4 px-6">
                          <span className={`px-2 py-1 rounded-full text-xs font-semibold ${isPaid ? "bg-emerald-100 text-emerald-700" : "bg-amber-100 text-amber-700"}`}>
                            {isPaid ? "paid" : "pending"}
                          </span>
                        </td>
                        <td className="py-4 px-6">{isPaid && paidDate === "—" ? "Processing..." : paidDate}</td>
                        <td className="py-4 px-6 text-sm text-gray-700">{transactionId}</td>
                        <td className="py-4 px-6 text-sm text-gray-700">{stripePaymentIntentId}</td>
                        <td className="py-4 px-6">
                          {isPaid ? (
                            <span className="inline-flex px-3 py-1 rounded-full text-xs font-semibold bg-emerald-100 text-emerald-700">
                              Paid
                            </span>
                          ) : (
                            <button
                              onClick={() => paySalary(admin, monthKey)}
                              disabled={rowPaying || currentUserRole !== "superadmin"}
                              className="px-4 py-2 rounded-lg bg-violet-600 text-white hover:bg-violet-700 disabled:opacity-50"
                            >
                              {rowPaying ? "Paying..." : "Pay Salary"}
                            </button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                  {admins.length === 0 && (
                    <tr>
                      <td colSpan="9" className="text-center py-12 text-gray-500">
                        No admins available for payroll.
                      </td>
                    </tr>
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {activeTab === "logs" && <LogsTab isSuperAdmin />}

        {activeTab === "deleted_records" && (
          <DeletedRecordsTab adminProfile={currentUserProfile} />
        )}

        {activeTab === "admin_reports" && <AdminReportsTab />}

      </div>

      <DeleteConfirmModal
        isOpen={deleteModal.open}
        onClose={() => !deleting && setDeleteModal({ open: false, admin: null })}
        onConfirm={handleConfirmDeleteAdmin}
        title="Remove admin"
        description="This admin will be moved to deleted admins and can be restored later."
        itemName={deleteModal.admin?.email}
        confirmLabel="Soft delete admin"
        isLoading={deleting}
      />

      {salaryPaymentDialog.open && (
        <div className="fixed inset-0 z-[9997] flex items-center justify-center p-4">
          <div
            className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm"
            onClick={() => {
              if (salaryPaymentSubmitting) return;
              setSalaryPaymentDialog({
                open: false,
                admin: null,
                clientSecret: "",
                paymentIntentId: "",
                salaryDocId: "",
                monthKey: "",
                amount: 40000,
              });
              setSalaryPaymentError("");
            }}
          />
          <div className="relative w-full max-w-xl rounded-2xl bg-white border border-gray-100 shadow-2xl p-6">
            <h3 className="text-xl font-semibold text-gray-800 mb-2">
              Pay Salary via Stripe
            </h3>
            <p className="text-sm text-gray-600 mb-4">
              Admin:{" "}
              {salaryPaymentDialog.admin?.name ||
                salaryPaymentDialog.admin?.email ||
                "Admin"}
            </p>
            <p className="text-sm text-gray-600 mb-4">
              Amount: PKR {Number(salaryPaymentDialog.amount || 0).toFixed(2)}
            </p>
            {salaryPaymentError && (
              <div className="mb-3 rounded-lg border border-rose-200 bg-rose-50 text-rose-700 px-3 py-2 text-sm">
                {salaryPaymentError}
              </div>
            )}
            <Elements stripe={stripePromise} options={{ clientSecret: salaryPaymentDialog.clientSecret }}>
              <SalaryStripePaymentForm
                onCancel={() => {
                  if (salaryPaymentSubmitting) return;
                  setSalaryPaymentDialog({
                    open: false,
                    admin: null,
                    clientSecret: "",
                    paymentIntentId: "",
                    salaryDocId: "",
                    monthKey: "",
                    amount: 40000,
                  });
                  setSalaryPaymentError("");
                }}
                onSuccess={handleSalaryStripeSuccess}
                setErrorMessage={setSalaryPaymentError}
                setIsSubmitting={setSalaryPaymentSubmitting}
              />
            </Elements>
          </div>
        </div>
      )}

      {viewAdminModal.open && viewAdminModal.admin && (
        <div
          className="fixed inset-0 z-[9998] flex items-center justify-center p-4"
          onClick={() => setViewAdminModal({ open: false, admin: null })}
        >
          <div className="absolute inset-0 bg-slate-900/60 backdrop-blur-sm" />
          <div
            className="relative w-full max-w-xl rounded-2xl bg-white shadow-2xl border border-gray-100 p-6"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-xl font-semibold text-gray-800">Admin Profile</h3>
              <button
                onClick={() => setViewAdminModal({ open: false, admin: null })}
                className="text-gray-500 hover:text-gray-700"
              >
                ✕
              </button>
            </div>

            <div className="flex items-start gap-4">
              <div className="w-20 h-20 rounded-xl overflow-hidden border border-violet-200 bg-violet-100 flex items-center justify-center text-violet-700 text-xl font-semibold">
                {getAdminProfileImage(viewAdminModal.admin).length > 0 ? (
                  <img
                    src={getAdminProfileImage(viewAdminModal.admin)}
                    alt={getAdminName(viewAdminModal.admin)}
                    className="w-full h-full object-cover"
                  />
                ) : (
                  <span>{getAdminEmail(viewAdminModal.admin).charAt(0).toUpperCase() || "A"}</span>
                )}
              </div>
              <div className="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-y-2 gap-x-4 text-sm">
                <p><span className="font-semibold text-gray-700">Name:</span> {getAdminName(viewAdminModal.admin)}</p>
                <p><span className="font-semibold text-gray-700">Email:</span> {getAdminEmail(viewAdminModal.admin)}</p>
                <p><span className="font-semibold text-gray-700">Role:</span> {String(viewAdminModal.admin.role || "Not provided")}</p>
                <p><span className="font-semibold text-gray-700">City:</span> {String(viewAdminModal.admin.city || "Not provided")}</p>
                <p><span className="font-semibold text-gray-700">Status:</span> {getStatusLabel(viewAdminModal.admin)}</p>
                <p><span className="font-semibold text-gray-700">Created At:</span> {formatCreatedAt(viewAdminModal.admin.createdAt)}</p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default SuperAdminDashboard;