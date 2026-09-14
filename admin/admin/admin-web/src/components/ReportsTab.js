import React, { useMemo, useState } from "react";

const metricCardStyle = {
  positive: "from-emerald-500 to-teal-500",
  neutral: "from-slate-500 to-slate-600",
  negative: "from-rose-500 to-red-500",
  info: "from-cyan-500 to-blue-500",
  warning: "from-amber-500 to-orange-500",
  purple: "from-violet-500 to-purple-500",
};

const formatAverage = (value) => {
  if (!Number.isFinite(value) || value <= 0) return "—";
  return value.toFixed(2);
};

const normalizeText = (value) => String(value || "").trim().toLowerCase();

const ReportsTab = ({
  drivers = [],
  parents = [],
  rides = [],
  reviews = [],
}) => {
  const [selectedDriverId, setSelectedDriverId] = useState(null);

  const driverPerformanceRows = useMemo(() => {
    const ridesCountByDriver = rides.reduce((acc, ride) => {
      const driverId = String(ride?.driverId || "").trim();
      if (!driverId) return acc;
      acc[driverId] = (acc[driverId] || 0) + 1;
      return acc;
    }, {});

    const reviewStatsByDriver = reviews.reduce((acc, review) => {
      const driverId = String(review?.driverId || "").trim();
      if (!driverId) return acc;
      const rating = Number(review?.rating || 0);
      if (!acc[driverId]) {
        acc[driverId] = { totalReviews: 0, ratingSum: 0, ratedCount: 0 };
      }
      acc[driverId].totalReviews += 1;
      if (Number.isFinite(rating) && rating > 0) {
        acc[driverId].ratingSum += rating;
        acc[driverId].ratedCount += 1;
      }
      return acc;
    }, {});

    return drivers
      .map((driver) => {
        const driverId = String(driver.id || "").trim();
        const reviewStats = reviewStatsByDriver[driverId] || {
          totalReviews: 0,
          ratingSum: 0,
          ratedCount: 0,
        };
        const totalReviews = reviewStats.totalReviews;
        const avgRating = reviewStats.ratedCount > 0
          ? reviewStats.ratingSum / reviewStats.ratedCount
          : 0;
        return {
          id: driverId,
          name: driver?.name || driver?.email || "Unnamed Driver",
          totalRides: ridesCountByDriver[driverId] || 0,
          totalReviews,
          avgRating,
        };
      })
      .sort((a, b) => b.totalRides - a.totalRides);
  }, [drivers, rides, reviews]);

  const selectedDriverReport = useMemo(() => {
    if (!selectedDriverId) return null;

    const selectedDriver = drivers.find(
      (driver) => String(driver?.id || "").trim() === selectedDriverId,
    );
    if (!selectedDriver) return null;

    const driverRides = rides.filter(
      (ride) => String(ride?.driverId || "").trim() === selectedDriverId,
    );
    const completedRides = driverRides.filter(
      (ride) => normalizeText(ride?.rideStatus) === "completed",
    ).length;

    const driverReviews = reviews
      .filter((review) => String(review?.driverId || "").trim() === selectedDriverId)
      .sort((a, b) => {
        const aTime = a?.createdAt?.toDate?.()?.getTime?.() || 0;
        const bTime = b?.createdAt?.toDate?.()?.getTime?.() || 0;
        return bTime - aTime;
      });

    const ratingStats = driverReviews.reduce(
      (acc, review) => {
        const rating = Number(review?.rating || 0);
        if (Number.isFinite(rating) && rating > 0) {
          acc.sum += rating;
          acc.count += 1;
        }
        return acc;
      },
      { sum: 0, count: 0 },
    );

    const sentimentStats = driverReviews.reduce(
      (acc, review) => {
        const sentiment = normalizeText(review?.sentiment);
        if (sentiment === "positive") acc.positive += 1;
        if (sentiment === "neutral") acc.neutral += 1;
        if (sentiment === "negative") acc.negative += 1;
        return acc;
      },
      { positive: 0, neutral: 0, negative: 0 },
    );

    const avgRating = ratingStats.count > 0 ? ratingStats.sum / ratingStats.count : 0;

    return {
      id: selectedDriverId,
      name: selectedDriver?.name || selectedDriver?.email || "Unnamed Driver",
      totalRides: driverRides.length,
      completedRides,
      avgRating,
      totalReviews: driverReviews.length,
      positiveReviews: sentimentStats.positive,
      neutralReviews: sentimentStats.neutral,
      negativeReviews: sentimentStats.negative,
      recentReviews: driverReviews.slice(0, 5),
    };
  }, [selectedDriverId, drivers, rides, reviews]);

  const reviewAnalytics = useMemo(() => {
    return reviews.reduce(
      (acc, review) => {
        const sentiment = normalizeText(review?.sentiment);
        const status = normalizeText(review?.status);
        acc.total += 1;
        if (sentiment === "positive") acc.positive += 1;
        if (sentiment === "neutral") acc.neutral += 1;
        if (sentiment === "negative") acc.negative += 1;
        if (status === "resolved") acc.resolved += 1;
        if (status === "under_review") acc.underReview += 1;
        return acc;
      },
      {
        total: 0,
        positive: 0,
        neutral: 0,
        negative: 0,
        resolved: 0,
        underReview: 0,
      },
    );
  }, [reviews]);

  const systemOverview = useMemo(() => {
    const approvedDrivers = drivers.filter(
      (driver) => normalizeText(driver?.status) === "approved",
    ).length;
    const pendingDrivers = drivers.filter(
      (driver) => normalizeText(driver?.status) === "pending",
    ).length;

    return {
      totalDrivers: drivers.length,
      totalParents: parents.length,
      approvedDrivers,
      pendingDrivers,
    };
  }, [drivers, parents]);

  const reviewCards = [
    {
      label: "Total Reviews",
      value: reviewAnalytics.total,
      tone: metricCardStyle.info,
    },
    {
      label: "Positive Reviews",
      value: reviewAnalytics.positive,
      tone: metricCardStyle.positive,
    },
    {
      label: "Neutral Reviews",
      value: reviewAnalytics.neutral,
      tone: metricCardStyle.neutral,
    },
    {
      label: "Negative Reviews",
      value: reviewAnalytics.negative,
      tone: metricCardStyle.negative,
    },
    {
      label: "Resolved Reviews",
      value: reviewAnalytics.resolved,
      tone: metricCardStyle.purple,
    },
    {
      label: "Under Review Reviews",
      value: reviewAnalytics.underReview,
      tone: metricCardStyle.warning,
    },
  ];

  const systemCards = [
    {
      label: "Total Drivers",
      value: systemOverview.totalDrivers,
      tone: metricCardStyle.info,
    },
    {
      label: "Total Parents",
      value: systemOverview.totalParents,
      tone: metricCardStyle.positive,
    },
    {
      label: "Approved Drivers",
      value: systemOverview.approvedDrivers,
      tone: metricCardStyle.purple,
    },
    {
      label: "Pending Drivers",
      value: systemOverview.pendingDrivers,
      tone: metricCardStyle.warning,
    },
  ];

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold bg-gradient-to-r from-emerald-600 to-teal-600 bg-clip-text text-transparent">
          Reports
        </h1>
        <p className="text-slate-600 mt-1">
          Read-only analytics for drivers, reviews, and system usage
        </p>
      </div>

      <section className="space-y-4">
        <h2 className="text-xl font-semibold text-slate-800">Driver Performance Report</h2>
        <div className="bg-white rounded-2xl border border-slate-100 shadow-lg overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full min-w-[640px]">
              <thead className="bg-slate-50">
                <tr className="text-left">
                  <th className="px-6 py-4 text-xs font-semibold tracking-wide text-slate-500 uppercase">
                    Driver Name
                  </th>
                  <th className="px-6 py-4 text-xs font-semibold tracking-wide text-slate-500 uppercase">
                    Total Rides
                  </th>
                  <th className="px-6 py-4 text-xs font-semibold tracking-wide text-slate-500 uppercase">
                    Avg Rating
                  </th>
                  <th className="px-6 py-4 text-xs font-semibold tracking-wide text-slate-500 uppercase">
                    Total Reviews
                  </th>
                </tr>
              </thead>
              <tbody>
                {driverPerformanceRows.length === 0 ? (
                  <tr>
                    <td className="px-6 py-8 text-slate-500 text-sm" colSpan={4}>
                      No driver report data found.
                    </td>
                  </tr>
                ) : (
                  driverPerformanceRows.map((row, index) => (
                    <tr
                      key={row.id || `driver-row-${index}`}
                      className="border-t border-slate-100 hover:bg-slate-50/70 transition-colors cursor-pointer"
                      onClick={() => setSelectedDriverId(row.id || null)}
                    >
                      <td className="px-6 py-4 text-sm font-medium text-slate-800">{row.name}</td>
                      <td className="px-6 py-4 text-sm text-slate-700">{row.totalRides}</td>
                      <td className="px-6 py-4 text-sm text-slate-700">{formatAverage(row.avgRating)}</td>
                      <td className="px-6 py-4 text-sm text-slate-700">{row.totalReviews}</td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>
      </section>

      {selectedDriverReport && (
        <section className="space-y-4">
          <div className="flex items-center justify-between gap-3">
            <h2 className="text-xl font-semibold text-slate-800">Driver Report Detail</h2>
            <button
              onClick={() => setSelectedDriverId(null)}
              className="px-4 py-2 rounded-lg text-sm font-medium bg-slate-100 text-slate-700 hover:bg-slate-200 transition-colors"
            >
              Back to list
            </button>
          </div>

          <div className="bg-white rounded-2xl border border-slate-100 shadow-lg p-6 space-y-6">
            <div>
              <p className="text-sm text-slate-500">Driver Name</p>
              <p className="text-2xl font-bold text-slate-800 mt-1">{selectedDriverReport.name}</p>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
              <div className="rounded-xl bg-slate-50 border border-slate-100 p-4">
                <p className="text-xs uppercase tracking-wide text-slate-500">Total Rides</p>
                <p className="text-2xl font-bold text-slate-800 mt-1">{selectedDriverReport.totalRides}</p>
              </div>
              <div className="rounded-xl bg-slate-50 border border-slate-100 p-4">
                <p className="text-xs uppercase tracking-wide text-slate-500">Completed Rides</p>
                <p className="text-2xl font-bold text-slate-800 mt-1">{selectedDriverReport.completedRides}</p>
              </div>
              <div className="rounded-xl bg-slate-50 border border-slate-100 p-4">
                <p className="text-xs uppercase tracking-wide text-slate-500">Avg Rating</p>
                <p className="text-2xl font-bold text-slate-800 mt-1">{formatAverage(selectedDriverReport.avgRating)}</p>
              </div>
              <div className="rounded-xl bg-slate-50 border border-slate-100 p-4">
                <p className="text-xs uppercase tracking-wide text-slate-500">Total Reviews</p>
                <p className="text-2xl font-bold text-slate-800 mt-1">{selectedDriverReport.totalReviews}</p>
              </div>
            </div>

            <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
              <div className="rounded-xl bg-emerald-50 border border-emerald-100 p-4">
                <p className="text-xs uppercase tracking-wide text-emerald-700">Positive Reviews</p>
                <p className="text-2xl font-bold text-emerald-700 mt-1">{selectedDriverReport.positiveReviews}</p>
              </div>
              <div className="rounded-xl bg-slate-100 border border-slate-200 p-4">
                <p className="text-xs uppercase tracking-wide text-slate-700">Neutral Reviews</p>
                <p className="text-2xl font-bold text-slate-700 mt-1">{selectedDriverReport.neutralReviews}</p>
              </div>
              <div className="rounded-xl bg-rose-50 border border-rose-100 p-4">
                <p className="text-xs uppercase tracking-wide text-rose-700">Negative Reviews</p>
                <p className="text-2xl font-bold text-rose-700 mt-1">{selectedDriverReport.negativeReviews}</p>
              </div>
            </div>

            <div className="space-y-3">
              <h3 className="text-lg font-semibold text-slate-800">Recent Reviews (Last 5)</h3>
              {selectedDriverReport.recentReviews.length === 0 ? (
                <div className="rounded-xl border border-slate-100 bg-slate-50 p-4 text-sm text-slate-500">
                  No reviews found for this driver.
                </div>
              ) : (
                <div className="space-y-2">
                  {selectedDriverReport.recentReviews.map((review, index) => {
                    const comment = String(review?.comment || "").trim();
                    const rating = Number(review?.rating || 0);
                    const sentiment = normalizeText(review?.sentiment) || "neutral";
                    return (
                      <div
                        key={review?.id || `recent-review-${index}`}
                        className="rounded-xl border border-slate-100 bg-slate-50 p-4"
                      >
                        <p className="text-sm font-medium text-slate-800">
                          Rating: {Number.isFinite(rating) && rating > 0 ? `${rating}/5` : "—"}
                          {" • "}
                          Sentiment: {sentiment}
                        </p>
                        <p className="text-sm text-slate-600 mt-1">{comment || "No comment provided."}</p>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          </div>
        </section>
      )}

      <section className="space-y-4">
        <h2 className="text-xl font-semibold text-slate-800">Review Analytics</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-3 gap-4">
          {reviewCards.map((card) => (
            <div
              key={card.label}
              className={`rounded-2xl p-5 text-white shadow-lg bg-gradient-to-r ${card.tone}`}
            >
              <p className="text-sm text-white/90">{card.label}</p>
              <p className="text-3xl font-bold mt-2">{card.value}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="space-y-4">
        <h2 className="text-xl font-semibold text-slate-800">System Overview</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
          {systemCards.map((card) => (
            <div
              key={card.label}
              className={`rounded-2xl p-5 text-white shadow-lg bg-gradient-to-r ${card.tone}`}
            >
              <p className="text-sm text-white/90">{card.label}</p>
              <p className="text-3xl font-bold mt-2">{card.value}</p>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
};

export default ReportsTab;
