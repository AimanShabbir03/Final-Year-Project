// src/components/PendingApprovals.js
import React, { useEffect, useState } from "react";
import { db } from "../firebase";
import { collection, getDocs, doc, updateDoc } from "firebase/firestore";

const PendingApprovals = () => {
  const [pendingDrivers, setPendingDrivers] = useState([]);
  const [loadingIds, setLoadingIds] = useState([]); // track which drivers are being updated

  const fetchPendingDrivers = async () => {
    try {
      const querySnapshot = await getDocs(collection(db, "users"));
      const pending = querySnapshot.docs
        .map(doc => ({ id: doc.id, ...doc.data() }))
        .filter(user => user.role === "driver" && user.status === "pending");
      setPendingDrivers(pending);
    } catch (err) {
      console.error("Error fetching pending drivers:", err);
    }
  };

  useEffect(() => {
    fetchPendingDrivers();
  }, []);

  const updateDriverStatus = async (id, status) => {
    try {
      setLoadingIds(prev => [...prev, id]);
      const driverRef = doc(db, "users", id);
      await updateDoc(driverRef, { status });
      // remove from pendingDrivers immediately for faster UI feedback
      setPendingDrivers(prev => prev.filter(driver => driver.id !== id));
    } catch (err) {
      console.error(`Error updating driver status to ${status}:`, err);
    } finally {
      setLoadingIds(prev => prev.filter(driverId => driverId !== id));
    }
  };

  return (
    <div className="bg-white shadow rounded p-6">
      <h2 className="text-xl font-bold mb-4">Pending Driver Requests</h2>
      {pendingDrivers.length === 0 ? (
        <p className="text-gray-600">No pending requests</p>
      ) : (
        <div className="overflow-x-auto">
          <table className="min-w-full bg-white border border-gray-200">
            <thead className="bg-gray-100">
              <tr>
                <th className="text-left p-3 border-b">Name</th>
                <th className="text-left p-3 border-b">Email</th>
                <th className="text-left p-3 border-b">Actions</th>
              </tr>
            </thead>
            <tbody>
              {pendingDrivers.map(driver => (
                <tr key={driver.id} className="hover:bg-gray-50">
                  <td className="p-3 border-b">{driver.name}</td>
                  <td className="p-3 border-b">{driver.email}</td>
                  <td className="p-3 border-b space-x-2">
                    <button
                      className={`bg-green-500 text-white px-3 py-1 rounded hover:bg-green-600 ${
                        loadingIds.includes(driver.id) ? "opacity-50 cursor-not-allowed" : ""
                      }`}
                      onClick={() => updateDriverStatus(driver.id, "active")}
                      disabled={loadingIds.includes(driver.id)}
                    >
                      Approve
                    </button>
                    <button
                      className={`bg-red-500 text-white px-3 py-1 rounded hover:bg-red-600 ${
                        loadingIds.includes(driver.id) ? "opacity-50 cursor-not-allowed" : ""
                      }`}
                      onClick={() => updateDriverStatus(driver.id, "rejected")}
                      disabled={loadingIds.includes(driver.id)}
                    >
                      Reject
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
};

export default PendingApprovals;
