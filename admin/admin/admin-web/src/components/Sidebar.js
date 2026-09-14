// src/components/Sidebar.js
import React from "react";
import { NavLink } from "react-router-dom";

const Sidebar = () => {
  const linkClasses = "block py-3 px-4 rounded hover:bg-gray-200 transition-colors";

  return (
    <div className="w-64 bg-gray-100 min-h-screen p-6 flex flex-col">
      <h2 className="text-2xl font-bold mb-6">Admin Panel</h2>
      <nav className="flex flex-col space-y-2">
        <NavLink
          to="/dashboard"
          className={({ isActive }) =>
            `${linkClasses} ${isActive ? "bg-gray-300 font-semibold" : ""}`
          }
        >
          Dashboard
        </NavLink>
        <NavLink
          to="/users"
          className={({ isActive }) =>
            `${linkClasses} ${isActive ? "bg-gray-300 font-semibold" : ""}`
          }
        >
          Users
        </NavLink>
        <NavLink
          to="/pending-approvals"
          className={({ isActive }) =>
            `${linkClasses} ${isActive ? "bg-gray-300 font-semibold" : ""}`
          }
        >
          Pending Approvals
        </NavLink>
      </nav>
    </div>
  );
};

export default Sidebar;
