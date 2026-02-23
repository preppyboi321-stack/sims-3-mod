/*
 * Sims 3 Turbo Engine Mod v1.1
 * ============================
 * Verified method signatures from decompiled ScriptCore.dll / SimIFace.dll
 *
 * GLOBAL methods (apply once):
 *   RouteManager.SetCarSpeedGlobalMultiplier(float multiplier)
 *   RouteManager.SetMinimumDistanceForCarTravel(float minDist)
 *   RouteManager.SetMinimumDistanceForBoatTravel(float minDist)
 *   RouteManager.SetTravellingEventInterval(float interval)
 *
 * PER-SIM methods (need ObjectGuid):
 *   RouteManager.SetAvoidanceFieldUseAdvancedAvoidance(ObjectGuid simObjId, bool use)
 *   RouteManager.SetShouldHandleObstructionsEncountered(ObjectGuid simObjId, bool b)
 *   RouteManager.SetAvoidanceFieldRangeScale(ObjectGuid simObjId, float scale)
 *   RouteManager.SetAvoidanceFieldSmoothing(ObjectGuid simObjId, float smoothing)
 *
 * PER-PAIR methods:
 *   RouteManager.InitShutdownPairedAvoidance(ulong master, ulong slave, uint slaveAGS, bool bInit)
 *
 * Build: csc /target:library /out:TurboEngine.dll /reference:ScriptCore.dll /reference:SimIFace.dll TurboEngine.cs
 * Target: .NET 2.0 / Mono
 */

using System;
using System.Collections.Generic;
using Sims3.SimIFace;

namespace TurboEngine
{
    public class TurboEngineInit
    {
        // ===== INSTANTIATOR =====
        [Tunable]
        internal static bool kInstantiator = false;

        // ===== GLOBAL ROUTING =====
        [Tunable]
        internal static float kCarSpeedMultiplier = 2.5f;

        [Tunable]
        internal static float kMinCarTravelDistance = 5.0f;

        [Tunable]
        internal static float kMinBoatTravelDistance = 5.0f;

        [Tunable]
        internal static float kTravellingEventInterval = 5.0f;

        // ===== PER-SIM ROUTING =====
        [Tunable]
        internal static bool kUseAdvancedAvoidance = false;

        [Tunable]
        internal static bool kShouldHandleObstructions = false;

        [Tunable]
        internal static float kAvoidanceRangeScale = 0.5f;

        [Tunable]
        internal static float kAvoidanceSmoothing = 0.0f;

        // ===== MAINTENANCE =====
        [Tunable]
        internal static float kMaintenanceIntervalMinutes = 30.0f;

        [Tunable]
        internal static bool kEnableMaintenance = true;

        [Tunable]
        internal static bool kForceGC = true;

        [Tunable]
        internal static bool kEnableLog = true;

        private static AlarmHandle sMaintenanceAlarm = AlarmHandle.kInvalidHandle;

        static TurboEngineInit()
        {
            World.sOnWorldLoadFinishedEventHandler += OnWorldLoadFinished;
            World.sOnWorldQuitEventHandler += OnWorldQuit;
        }

        private static void Log(string msg)
        {
            if (!kEnableLog) return;
            try { Simulator.AppendToScriptErrorFile("[TurboEngine] " + msg); }
            catch { }
        }

        // ================================================================
        // WORLD LOAD
        // ================================================================

        private static void OnWorldLoadFinished(object sender, EventArgs e)
        {
            try
            {
                int g = ApplyGlobalOptimizations();
                int s = ApplyPerSimOptimizations();

                if (kEnableMaintenance)
                    StartMaintenance();

                Log("v1.1 loaded! Global: " + g + "/4 applied. Per-sim optimized: " + s + " objects.");
            }
            catch (Exception ex)
            {
                Log("Init error: " + ex.Message);
            }
        }

        private static void OnWorldQuit(object sender, EventArgs e)
        {
            StopMaintenance();
        }

        // ================================================================
        // GLOBAL OPTIMIZATIONS — one-time, affect entire routing engine
        // ================================================================

        private static int ApplyGlobalOptimizations()
        {
            int applied = 0;

            try { RouteManager.SetCarSpeedGlobalMultiplier(kCarSpeedMultiplier); applied++; }
            catch (Exception ex) { Log("CarSpeedGlobal: " + ex.Message); }

            try { RouteManager.SetMinimumDistanceForCarTravel(kMinCarTravelDistance); applied++; }
            catch (Exception ex) { Log("MinDistCar: " + ex.Message); }

            try { RouteManager.SetMinimumDistanceForBoatTravel(kMinBoatTravelDistance); applied++; }
            catch (Exception ex) { Log("MinDistBoat: " + ex.Message); }

            try { RouteManager.SetTravellingEventInterval(kTravellingEventInterval); applied++; }
            catch (Exception ex) { Log("TravelInterval: " + ex.Message); }

            return applied;
        }

        // ================================================================
        // PER-SIM OPTIMIZATIONS — iterate all objects in the scene
        // ================================================================

        private static int ApplyPerSimOptimizations()
        {
            int count = 0;

            try
            {
                // Enumerate all game objects and apply routing optimizations.
                // Non-routing objects will silently ignore these calls.
                ObjectGuid[] objects = null;

                try
                {
                    objects = Simulator.GetObjectsInScene();
                }
                catch
                {
                    // Method may not exist in all versions — fall back
                }

                if (objects != null && objects.Length > 0)
                {
                    foreach (ObjectGuid objId in objects)
                    {
                        if (OptimizeObject(objId))
                            count++;
                    }
                }
                else
                {
                    Log("No objects found via GetObjectsInScene — per-sim skipped.");
                }
            }
            catch (Exception ex)
            {
                Log("PerSim error: " + ex.Message);
            }

            return count;
        }

        /// <summary>
        /// Apply per-object routing optimizations.
        /// Safe to call on any ObjectGuid — non-routing objects simply ignore it.
        /// </summary>
        private static bool OptimizeObject(ObjectGuid objId)
        {
            bool any = false;

            // Disable advanced avoidance field — biggest per-sim CPU saver.
            // Advanced avoidance recalculates collision fields per sim pair per tick.
            try { RouteManager.SetAvoidanceFieldUseAdvancedAvoidance(objId, kUseAdvancedAvoidance); any = true; }
            catch { }

            // Disable dynamic obstruction re-routing — use simple collision instead
            try { RouteManager.SetShouldHandleObstructionsEncountered(objId, kShouldHandleObstructions); any = true; }
            catch { }

            // Halve the avoidance check radius
            try { RouteManager.SetAvoidanceFieldRangeScale(objId, kAvoidanceRangeScale); any = true; }
            catch { }

            // Zero smoothing passes on avoidance field
            try { RouteManager.SetAvoidanceFieldSmoothing(objId, kAvoidanceSmoothing); any = true; }
            catch { }

            return any;
        }

        // ================================================================
        // MAINTENANCE — periodic re-apply + garbage collection
        // ================================================================

        private static void StartMaintenance()
        {
            try
            {
                sMaintenanceAlarm = AlarmManager.Global.AddAlarmRepeating(
                    kMaintenanceIntervalMinutes,
                    TimeUnit.Minutes,
                    OnMaintenanceTick,
                    kMaintenanceIntervalMinutes,
                    TimeUnit.Minutes,
                    "TurboEngine_Maintenance",
                    AlarmType.NeverPersisted,
                    null
                );
                Log("Maintenance started (every " + kMaintenanceIntervalMinutes + " min)");
            }
            catch (Exception ex)
            {
                Log("Maintenance alarm failed: " + ex.Message);
            }
        }

        private static void StopMaintenance()
        {
            if (sMaintenanceAlarm != AlarmHandle.kInvalidHandle)
            {
                try { AlarmManager.Global.RemoveAlarm(sMaintenanceAlarm); } catch { }
                sMaintenanceAlarm = AlarmHandle.kInvalidHandle;
            }
        }

        private static void OnMaintenanceTick()
        {
            try
            {
                // Re-apply globals (reset on lot transitions)
                ApplyGlobalOptimizations();

                // Re-apply per-sim (new sims may have spawned since last run)
                ApplyPerSimOptimizations();

                // Force GC to fight the notorious Sims 3 memory leak
                if (kForceGC)
                {
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    GC.Collect();
                }

                // Clear reflection cache to free managed memory
                try { Simulator.ClearReflectionCache(); } catch { }
            }
            catch { }
        }
    }
}
