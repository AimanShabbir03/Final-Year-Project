// src/components/Dashboard.js
import React, { useEffect, useState } from "react";
import { db } from "../firebase";
import { collection, getDocs, query, where } from "firebase/firestore";

const Dashboard = () => {
  const [users, setUsers] = useState([]);
  const [drivers, setDrivers] = useState([]);
  const [parents, setParents] = useState([]);

  const fetchData = async () => {
    const snapshot = await getDocs(collection(db, "users"));
    const allUsers = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
    setUsers(allUsers);
    setDrivers(allUsers.filter(u => u.role === "driver"));
    setParents(allUsers.filter(u => u.role === "parent"));
  };

  useEffect(() => {
    fetchData();
  }, []);

  return (
    <div>
      <h2>Dashboard</h2>
      <p>Total Users: {users.length}</p>
      <p>Total Drivers: {drivers.length}</p>
      <p>Total Parents: {parents.length}</p>
    </div>
  );
};

export default Dashboard;
