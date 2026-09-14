import React from "react";
import { BrowserRouter as Router, Routes, Route, Navigate } from "react-router-dom";
import Login from "./pages/Login";
import AdminDashboard from "./pages/AdminDashboard";
import SuperAdminDashboard from "./pages/SuperAdminDashboard"; // import superadmin

function App() {
  return (
    <Router>
      <Routes>
        <Route path="/" element={<Navigate to="/login" />} />
        <Route path="/login" element={<Login />} />

        {/* Admin Dashboard */}
        <Route path="/admin-dashboard/*" element={<AdminDashboard />} />

        {/* Super Admin Dashboard */}
        <Route path="/superadmin-dashboard/*" element={<SuperAdminDashboard />} />

        {/* fallback route for unknown URLs */}
        <Route path="*" element={<Navigate to="/login" />} />
      </Routes>
    </Router>
  );
}

export default App;
