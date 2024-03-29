/*
 * $Header: /cvshome/build/org.osgi.util.tracker/src/org/osgi/util/tracker/ServiceTracker.java,v 1.22 2006/07/20 16:14:43 hargrave Exp $
 *
 * Copyright (c) OSGi Alliance (2000, 2007). All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Port to the D programming language:
//     Frank Benoit <benoit@tionex.de>
module org.osgi.util.tracker.ServiceTracker;

import java.lang.all;

import org.osgi.util.tracker.ServiceTrackerCustomizer; // packageimport

import java.util.ArrayList;
import java.util.Enumeration;
import java.util.Hashtable;
import java.util.LinkedList;

import org.eclipse.osgi.framework.internal.core.FilterImpl;
import org.osgi.framework.AllServiceListener;
import org.osgi.framework.BundleContext;
import org.osgi.framework.Constants;
import org.osgi.framework.Filter;
import org.osgi.framework.InvalidSyntaxException;
import org.osgi.framework.ServiceEvent;
import org.osgi.framework.ServiceListener;
import org.osgi.framework.ServiceReference;

/**
 * The <code>ServiceTracker</code> class simplifies using services from the
 * Framework's service registry.
 * <p>
 * A <code>ServiceTracker</code> object is constructed with search criteria
 * and a <code>ServiceTrackerCustomizer</code> object. A
 * <code>ServiceTracker</code> object can use the
 * <code>ServiceTrackerCustomizer</code> object to customize the service
 * objects to be tracked. The <code>ServiceTracker</code> object can then be
 * opened to begin tracking all services in the Framework's service registry
 * that match the specified search criteria. The <code>ServiceTracker</code>
 * object correctly handles all of the details of listening to
 * <code>ServiceEvent</code> objects and getting and ungetting services.
 * <p>
 * The <code>getServiceReferences</code> method can be called to get
 * references to the services being tracked. The <code>getService</code> and
 * <code>getServices</code> methods can be called to get the service objects
 * for the tracked service.
 * <p>
 * The <code>ServiceTracker</code> class is thread-safe. It does not call a
 * <code>ServiceTrackerCustomizer</code> object while holding any locks.
 * <code>ServiceTrackerCustomizer</code> implementations must also be
 * thread-safe.
 *
 * @ThreadSafe
 * @version $Revision: 1.29 $
 */

/*
 * This implementation has been customized to only work with the Equinox OSGi framework.
 * In all cases a filter string containing objectClass is passed to BundleContext.addServiceListener
 * to take advantage of the ServiceEvent delivery optimizations.
 */

public class ServiceTracker : ServiceTrackerCustomizer {
    /* set this to true to compile in_ debug_ messages */
    static final bool               DEBUG           = false;
    /**
     * Bundle context against which this <code>ServiceTracker</code> object is
     * tracking.
     */
    protected final BundleContext       context;
    /**
     * Filter specifying search criteria for the services to track.
     *
     * @since 1.1
     */
    protected final Filter              filter;
    /**
     * <code>ServiceTrackerCustomizer</code> object for this tracker.
     */
    final ServiceTrackerCustomizer      customizer;
    /**
     * Filter string for use when adding the ServiceListener.
     */
    private final String                listenerFilter;
    /**
     * Class name to be tracked. If this field is set, then we are tracking by
     * class name.
     */
    private final String                trackClass;
    /**
     * Reference to be tracked. If this field is set, then we are tracking a
     * single ServiceReference.
     */
    private final ServiceReference      trackReference;
    /**
     * True if no Filter object was supplied in a constructor or we are not
     * using the supplied filter.
     */
    final bool                      noUserFilter;
    /**
     * Tracked services: <code>ServiceReference</code> object -> customized
     * Object and <code>ServiceListener</code> object
     */
    private /+volatile+/ Tracked            tracked;
    /**
     * Modification count. This field is initialized to zero by open, set to -1
     * by close and incremented by modified.
     *
     * This field is volatile since it is accessed by multiple threads.
     */
    private /+volatile+/ int                trackingCount   = -1;
    /**
     * Cached ServiceReference for getServiceReference.
     *
     * This field is volatile since it is accessed by multiple threads.
     */
    private /+volatile+/ ServiceReference   cachedReference;
    /**
     * Cached service object for getService.
     *
     * This field is volatile since it is accessed by multiple threads.
     */
    private /+volatile+/ Object             cachedService;

    /**
     * Create a <code>ServiceTracker</code> object on the specified
     * <code>ServiceReference</code> object.
     *
     * <p>
     * The service referenced by the specified <code>ServiceReference</code>
     * object will be tracked by this <code>ServiceTracker</code> object.
     *
     * @param context <code>BundleContext</code> object against which the
     *        tracking is done.
     * @param reference <code>ServiceReference</code> object for the service
     *        to be tracked.
     * @param customizer The customizer object to call when services are added,
     *        modified, or removed in this <code>ServiceTracker</code> object.
     *        If customizer is <code>null</code>, then this
     *        <code>ServiceTracker</code> object will be used as the
     *        <code>ServiceTrackerCustomizer</code> object and the
     *        <code>ServiceTracker</code> object will call the
     *        <code>ServiceTrackerCustomizer</code> methods on itself.
     */
    public this(BundleContext context, ServiceReference reference,
            ServiceTrackerCustomizer customizer) {
        this.context = context;
        this.trackReference = reference;
        this.trackClass = null;
        this.customizer = (customizer is null) ? this : customizer;
        this.listenerFilter = "(&(" + Constants.OBJECTCLASS + "=" + (stringcast( reference.getProperty(Constants.OBJECTCLASS)))[0] //$NON-NLS-1$ //$NON-NLS-2$
                + ")(" + Constants.SERVICE_ID + "=" + reference.getProperty(Constants.SERVICE_ID).toString() + "))" ; //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$
        this.noUserFilter = true;
        try {
            this.filter = context.createFilter(listenerFilter);
        }
        catch (InvalidSyntaxException e) { // we could only get this exception
            // if the ServiceReference was
            // invalid
            throw new IllegalArgumentException(
                    "unexpected InvalidSyntaxException: " + e.getMessage()); //$NON-NLS-1$
        }
    }

    /**
     * Create a <code>ServiceTracker</code> object on the specified class
     * name.
     *
     * <p>
     * Services registered under the specified class name will be tracked by
     * this <code>ServiceTracker</code> object.
     *
     * @param context <code>BundleContext</code> object against which the
     *        tracking is done.
     * @param clazz Class name of the services to be tracked.
     * @param customizer The customizer object to call when services are added,
     *        modified, or removed in this <code>ServiceTracker</code> object.
     *        If customizer is <code>null</code>, then this
     *        <code>ServiceTracker</code> object will be used as the
     *        <code>ServiceTrackerCustomizer</code> object and the
     *        <code>ServiceTracker</code> object will call the
     *        <code>ServiceTrackerCustomizer</code> methods on itself.
     */
    public this(BundleContext context, String clazz,
            ServiceTrackerCustomizer customizer) {
        this.context = context;
        this.trackReference = null;
        this.trackClass = clazz;
        this.customizer = (customizer is null) ? this : customizer;
        this.listenerFilter = "(" + Constants.OBJECTCLASS + "=" + clazz.toString() + ")"; //$NON-NLS-1$ //$NON-NLS-2$ //$NON-NLS-3$
        this.noUserFilter = true;
        try {
            this.filter = context.createFilter(listenerFilter);
        }
        catch (InvalidSyntaxException e) { // we could only get this exception
            // if the clazz argument was
            // malformed
            throw new IllegalArgumentException(
                    "unexpected InvalidSyntaxException: " + e.getMessage()); //$NON-NLS-1$
        }
    }

    /**
     * Create a <code>ServiceTracker</code> object on the specified
     * <code>Filter</code> object.
     *
     * <p>
     * Services which match the specified <code>Filter</code> object will be
     * tracked by this <code>ServiceTracker</code> object.
     *
     * @param context <code>BundleContext</code> object against which the
     *        tracking is done.
     * @param filter <code>Filter</code> object to select the services to be
     *        tracked.
     * @param customizer The customizer object to call when services are added,
     *        modified, or removed in this <code>ServiceTracker</code> object.
     *        If customizer is null, then this <code>ServiceTracker</code>
     *        object will be used as the <code>ServiceTrackerCustomizer</code>
     *        object and the <code>ServiceTracker</code> object will call the
     *        <code>ServiceTrackerCustomizer</code> methods on itself.
     * @since 1.1
     */
    public this(BundleContext context, Filter filter,
            ServiceTrackerCustomizer customizer) {
        this.context = context;
        this.trackReference = null;

        // obtain a required objectClass from the user supplied filter
        if ( null !is cast(FilterImpl)filter ) {
            this.trackClass = (cast(FilterImpl)filter).getRequiredObjectClass();
        } else {
            this.trackClass = null;
        }

        if (this.trackClass !is null) {
            this.listenerFilter = FilterImpl.getObjectClassFilterString(this.trackClass);
            //convert to track by class instead of filter if the user filter is in the form (objectClass=some.Clazz)
            this.noUserFilter = this.listenerFilter.opEquals(filter.toString());
        } else {
            this.listenerFilter = null;
            this.noUserFilter = false;
        }

        this.filter = filter;
        this.customizer = (customizer is null) ? this : customizer;
        if ((context is null) || (filter is null)) { // we throw a NPE here
            // to
            // be consistent with the
            // other constructors
            throw new NullPointerException();
        }
    }

    /**
     * Open this <code>ServiceTracker</code> object and begin tracking
     * services.
     *
     * <p>
     * This method calls <code>open(false)</code>.
     *
     * @throws java.lang.IllegalStateException if the <code>BundleContext</code>
     *         object with which this <code>ServiceTracker</code> object was
     *         created is no longer valid.
     * @see #open(boolean)
     */
    public void open() {
        open(false);
    }

    /**
     * Open this <code>ServiceTracker</code> object and begin tracking
     * services.
     *
     * <p>
     * Services which match the search criteria specified when this
     * <code>ServiceTracker</code> object was created are now tracked by this
     * <code>ServiceTracker</code> object.
     *
     * @param trackAllServices If <code>true</code>, then this
     *        <code>ServiceTracker</code> will track all matching services
     *        regardless of class loader accessibility. If <code>false</code>,
     *        then this <code>ServiceTracker</code> will only track matching
     *        services which are class loader accessibile to the bundle whose
     *        <code>BundleContext</code> is used by this
     *        <code>ServiceTracker</code>.
     * @throws java.lang.IllegalStateException if the <code>BundleContext</code>
     *         object with which this <code>ServiceTracker</code> object was
     *         created is no longer valid.
     * @since 1.3
     */
    public synchronized void open(bool trackAllServices) {
        if (tracked !is null) {
            return;
        }
        if (DEBUG) {
            System.out_.println("ServiceTracker.open: " + filter); //$NON-NLS-1$
        }
        tracked = trackAllServices ? new AllTracked() : new Tracked();
        trackingCount = 0;
        synchronized (tracked) {
            try {
                context.addServiceListener(tracked, listenerFilter);
                ServiceReference[] references;

                if (trackReference !is null) { // tracking a single reference
                    references = [ cast(ServiceReference)trackReference];
                }
                else { // tracking a set of references
                    references = getInitialReferences(trackAllServices, trackClass,
                            noUserFilter ? null: filter.toString());
                }

                tracked.setInitialServices(references); // set tracked with_
                // the initial
                // references
            }
            catch (InvalidSyntaxException e) {
                throw new RuntimeException(
                        "unexpected InvalidSyntaxException: " + e.getMessage()); //$NON-NLS-1$
            }
        }
        /* Call tracked outside of synchronized region */
        tracked.trackInitialServices(); // process the initial references
    }

    /**
     * Returns the list of initial <code>ServiceReference</code> objects that
     * will be tracked by this <code>ServiceTracker</code> object.
     *
     * @param trackAllServices If true, use getAllServiceReferences.
     * @param trackClass the class name with which the service was registered,
     *        or null for all services.
     * @param filterString the filter criteria or null for all services.
     * @return the list of initial <code>ServiceReference</code> objects.
     * @throws InvalidSyntaxException if the filter uses an invalid syntax.
     */
    private ServiceReference[] getInitialReferences(bool trackAllServices,
            String trackClass, String filterString) {
        if (trackAllServices) {
            return context.getAllServiceReferences(trackClass, filterString);
        }
        else {
            return context.getServiceReferences(trackClass, filterString);
        }
    }

    /**
     * Close this <code>ServiceTracker</code> object.
     *
     * <p>
     * This method should be called when this <code>ServiceTracker</code>
     * object should end the tracking of services.
     */
    public synchronized void close() {
        if (tracked is null) {
            return;
        }
        if (DEBUG) {
            System.out_.println("ServiceTracker.close: " + filter); //$NON-NLS-1$
        }
        tracked.close();
        ServiceReference[] references = getServiceReferences();
        Tracked outgoing = tracked;
        tracked = null;
        try {
            context.removeServiceListener(outgoing);
        }
        catch (IllegalStateException e) {
            /* In case the context was stopped. */
        }
        if (references !is null) {
            for (int i = 0; i < references.length_; i++) {
                outgoing.untrack(references[i]);
            }
        }
        trackingCount = -1;
        if (DEBUG) {
            if ((cachedReference is null) && (cachedService is null)) {
                System.out_
                        .println("ServiceTracker.close[cached cleared]: " + filter); //$NON-NLS-1$
            }
        }
    }

    /**
     * Default implementation of the
     * <code>ServiceTrackerCustomizer.addingService</code> method.
     *
     * <p>
     * This method is only called when this <code>ServiceTracker</code> object
     * has been constructed with a <code>null ServiceTrackerCustomizer</code>
     * argument.
     *
     * The default implementation returns the result of calling
     * <code>getService</code>, on the <code>BundleContext</code> object
     * with which this <code>ServiceTracker</code> object was created, passing
     * the specified <code>ServiceReference</code> object.
     * <p>
     * This method can be overridden in a subclass to customize the service
     * object to be tracked for the service being added. In that case, take care
     * not to rely on the default implementation of removedService that will
     * unget the service.
     *
     * @param reference Reference to service being added to this
     *        <code>ServiceTracker</code> object.
     * @return The service object to be tracked for the service added to this
     *         <code>ServiceTracker</code> object.
     * @see ServiceTrackerCustomizer
     */
    public Object addingService(ServiceReference reference) {
        return context.getService(reference);
    }

    /**
     * Default implementation of the
     * <code>ServiceTrackerCustomizer.modifiedService</code> method.
     *
     * <p>
     * This method is only called when this <code>ServiceTracker</code> object
     * has been constructed with a <code>null ServiceTrackerCustomizer</code>
     * argument.
     *
     * The default implementation does nothing.
     *
     * @param reference Reference to modified service.
     * @param service The service object for the modified service.
     * @see ServiceTrackerCustomizer
     */
    public void modifiedService(ServiceReference reference, Object service) {
    }

    /**
     * Default implementation of the
     * <code>ServiceTrackerCustomizer.removedService</code> method.
     *
     * <p>
     * This method is only called when this <code>ServiceTracker</code> object
     * has been constructed with a <code>null ServiceTrackerCustomizer</code>
     * argument.
     *
     * The default implementation calls <code>ungetService</code>, on the
     * <code>BundleContext</code> object with which this
     * <code>ServiceTracker</code> object was created, passing the specified
     * <code>ServiceReference</code> object.
     * <p>
     * This method can be overridden in a subclass. If the default
     * implementation of <code>addingService</code> method was used, this
     * method must unget the service.
     *
     * @param reference Reference to removed service.
     * @param service The service object for the removed service.
     * @see ServiceTrackerCustomizer
     */
    public void removedService(ServiceReference reference, Object service) {
        context.ungetService(reference);
    }

    /**
     * Wait for at least one service to be tracked by this
     * <code>ServiceTracker</code> object.
     * <p>
     * It is strongly recommended that <code>waitForService</code> is not used
     * during the calling of the <code>BundleActivator</code> methods.
     * <code>BundleActivator</code> methods are expected to complete in a
     * short period of time.
     *
     * @param timeout time interval in milliseconds to wait. If zero, the method
     *        will wait indefinately.
     * @return Returns the result of <code>getService()</code>.
     * @throws InterruptedException If another thread has interrupted the
     *         current thread.
     * @throws IllegalArgumentException If the value of timeout is negative.
     */
    public Object waitForService(long timeout) {
        if (timeout < 0) {
            throw new IllegalArgumentException("timeout value is_ negative"); //$NON-NLS-1$
        }
        Object object = getService();
        while (object is null) {
            Tracked tracked = this.tracked; /*
                                             * use local var since we are not
                                             * synchronized
                                             */
            if (tracked is null) { /* if ServiceTracker is_ not open */
                return null;
            }
            synchronized (tracked) {
                if (tracked.size() is 0) {
                    tracked.wait(timeout);
                }
            }
            object = getService();
            if (timeout > 0) {
                return object;
            }
        }
        return object;
    }

    /**
     * Return an array of <code>ServiceReference</code> objects for all
     * services being tracked by this <code>ServiceTracker</code> object.
     *
     * @return Array of <code>ServiceReference</code> objects or
     *         <code>null</code> if no service are being tracked.
     */
    public ServiceReference[] getServiceReferences() {
        Tracked tracked = this.tracked; /*
                                         * use local var since we are not
                                         * synchronized
                                         */
        if (tracked is null) { /* if ServiceTracker is_ not open */
            return null;
        }
        synchronized (tracked) {
            int length_ = tracked.size();
            if (length_ is 0) {
                return null;
            }
            ServiceReference[] references = new ServiceReference[length_];
            Enumeration keys = tracked.keys();
            for (int i = 0; i < length_; i++) {
                references[i] = cast(ServiceReference) keys.nextElement();
            }
            return references;
        }
    }

    /**
     * Returns a <code>ServiceReference</code> object for one of the services
     * being tracked by this <code>ServiceTracker</code> object.
     *
     * <p>
     * If multiple services are being tracked, the service with the highest
     * ranking (as specified in its <code>service.ranking</code> property) is
     * returned.
     *
     * <p>
     * If there is a tie in ranking, the service with the lowest service ID (as
     * specified in its <code>service.id</code> property); that is, the
     * service that was registered first is returned.
     * <p>
     * This is the same algorithm used by
     * <code>BundleContext.getServiceReference</code>.
     *
     * @return <code>ServiceReference</code> object or <code>null</code> if
     *         no service is being tracked.
     * @since 1.1
     */
    public ServiceReference getServiceReference() {
        ServiceReference reference = cachedReference;
        if (reference !is null) {
            if (DEBUG) {
                System.out_
                        .println("ServiceTracker.getServiceReference[cached]: " + filter); //$NON-NLS-1$
            }
            return reference;
        }
        if (DEBUG) {
            System.out_.println("ServiceTracker.getServiceReference: " + filter); //$NON-NLS-1$
        }
        ServiceReference[] references = getServiceReferences();
        int length_ = (references is null) ? 0 : references.length_;
        if (length_ is 0) /* if no service is_ being tracked */
        {
            return null;
        }
        int index = 0;
        if (length_ > 1) /* if more than one service, select highest ranking */
        {
            int rankings[] = new int[length_];
            int count = 0;
            int maxRanking = Integer.MIN_VALUE;
            for (int i = 0; i < length_; i++) {
                Object property = references[i]
                        .getProperty(Constants.SERVICE_RANKING);
                int ranking = ( null !is cast(Integer)property ) ? (cast(Integer) property)
                        .intValue()
                        : 0;
                rankings[i] = ranking;
                if (ranking > maxRanking) {
                    index = i;
                    maxRanking = ranking;
                    count = 1;
                }
                else {
                    if (ranking is maxRanking) {
                        count++;
                    }
                }
            }
            if (count > 1) /* if still more than one service, select lowest id */
            {
                long minId = Long.MAX_VALUE;
                for (int i = 0; i < length_; i++) {
                    if (rankings[i] is maxRanking) {
                        long id = (cast(Long) (references[i]
                                .getProperty(Constants.SERVICE_ID)))
                                .longValue();
                        if (id < minId) {
                            index = i;
                            minId = id;
                        }
                    }
                }
            }
        }
        return cachedReference = references[index];
    }

    /**
     * Returns the service object for the specified
     * <code>ServiceReference</code> object if the referenced service is being
     * tracked by this <code>ServiceTracker</code> object.
     *
     * @param reference Reference to the desired service.
     * @return Service object or <code>null</code> if the service referenced
     *         by the specified <code>ServiceReference</code> object is not
     *         being tracked.
     */
    public Object getService(ServiceReference reference) {
        Tracked tracked = this.tracked; /*
                                         * use local var since we are not
                                         * synchronized
                                         */
        if (tracked is null) { /* if ServiceTracker is_ not open */
            return null;
        }
        synchronized (tracked) {
            return tracked.get(reference);
        }
    }

    /**
     * Return an array of service objects for all services being tracked by this
     * <code>ServiceTracker</code> object.
     *
     * @return Array of service objects or <code>null</code> if no service are
     *         being tracked.
     */
    public Object[] getServices() {
        Tracked tracked = this.tracked; /*
                                         * use local var since we are not
                                         * synchronized
                                         */
        if (tracked is null) { /* if ServiceTracker is_ not open */
            return null;
        }
        synchronized (tracked) {
            ServiceReference[] references = getServiceReferences();
            int length_ = (references is null) ? 0 : references.length_;
            if (length_ is 0) {
                return null;
            }
            Object[] objects = new Object[length_];
            for (int i = 0; i < length_; i++) {
                objects[i] = getService(references[i]);
            }
            return objects;
        }
    }

    /**
     * Returns a service object for one of the services being tracked by this
     * <code>ServiceTracker</code> object.
     *
     * <p>
     * If any services are being tracked, this method returns the result of
     * calling <code>getService(getServiceReference())</code>.
     *
     * @return Service object or <code>null</code> if no service is being
     *         tracked.
     */
    public Object getService() {
        Object service = cachedService;
        if (service !is null) {
            if (DEBUG) {
                System.out_
                        .println("ServiceTracker.getService[cached]: " + filter); //$NON-NLS-1$
            }
            return service;
        }
        if (DEBUG) {
            System.out_.println("ServiceTracker.getService: " + filter); //$NON-NLS-1$
        }
        ServiceReference reference = getServiceReference();
        if (reference is null) {
            return null;
        }
        return cachedService = getService(reference);
    }

    /**
     * Remove a service from this <code>ServiceTracker</code> object.
     *
     * The specified service will be removed from this
     * <code>ServiceTracker</code> object. If the specified service was being
     * tracked then the <code>ServiceTrackerCustomizer.removedService</code>
     * method will be called for that service.
     *
     * @param reference Reference to the service to be removed.
     */
    public void remove(ServiceReference reference) {
        Tracked tracked = this.tracked; /*
                                         * use local var since we are not
                                         * synchronized
                                         */
        if (tracked is null) { /* if ServiceTracker is_ not open */
            return;
        }
        tracked.untrack(reference);
    }

    /**
     * Return the number of services being tracked by this
     * <code>ServiceTracker</code> object.
     *
     * @return Number of services being tracked.
     */
    public int size() {
        Tracked tracked = this.tracked; /*
                                         * use local var since we are not
                                         * synchronized
                                         */
        if (tracked is null) { /* if ServiceTracker is_ not open */
            return 0;
        }
        return tracked.size();
    }

    /**
     * Returns the tracking count for this <code>ServiceTracker</code> object.
     *
     * The tracking count is initialized to 0 when this
     * <code>ServiceTracker</code> object is opened. Every time a service is
     * added, modified or removed from this <code>ServiceTracker</code> object
     * the tracking count is incremented.
     *
     * <p>
     * The tracking count can be used to determine if this
     * <code>ServiceTracker</code> object has added, modified or removed a
     * service by comparing a tracking count value previously collected with the
     * current tracking count value. If the value has not changed, then no
     * service has been added, modified or removed from this
     * <code>ServiceTracker</code> object since the previous tracking count
     * was collected.
     *
     * @since 1.2
     * @return The tracking count for this <code>ServiceTracker</code> object
     *         or -1 if this <code>ServiceTracker</code> object is not open.
     */
    public int getTrackingCount() {
        return trackingCount;
    }

    /**
     * Called by the Tracked object whenever the set of tracked services is
     * modified. Increments the tracking count and clears the cache.
     *
     * @GuardedBy tracked
     */
    /*
     * This method must not be synchronized since it is called by Tracked while
     * Tracked is synchronized. We don't want synchronization interactions
     * between the ServiceListener thread and the user thread.
     */
    void modified() {
        trackingCount++; /* increment modification count */
        cachedReference = null; /* clear cached value */
        cachedService = null; /* clear cached value */
        if (DEBUG) {
            System.out_.println("ServiceTracker.modified: " + filter); //$NON-NLS-1$
        }
    }


    /**
     * Inner class to track services. If a <code>ServiceTracker</code> object
     * is reused (closed then reopened), then a new Tracked object is used. This
     * class is a hashtable mapping <code>ServiceReference</code> object ->
     * customized Object. This class is the <code>ServiceListener</code>
     * object for the tracker. This class is used to synchronize access to the
     * tracked services. This is not a public class. It is only for use by the
     * implementation of the <code>ServiceTracker</code> class.
     *
     * @ThreadSafe
     */
    class Tracked : Hashtable , ServiceListener {
        static final long           serialVersionUID    = -7420065199791006079L;
        /**
         * List of ServiceReferences in the process of being added. This is used
         * to deal with nesting of ServiceEvents. Since ServiceEvents are
         * synchronously delivered, ServiceEvents can be nested. For example,
         * when processing the adding of a service and the customizer causes the
         * service to be unregistered, notification to the nested call to
         * untrack that the service was unregistered can be made to the track
         * method.
         *
         * Since the ArrayList implementation is not synchronized, all access to
         * this list must be protected by the same synchronized object for
         * thread-safety.
         *
         * @GuardedBy this
         */
        private final ArrayList     adding;

        /**
         * true if the tracked object is closed.
         *
         * This field is volatile because it is set by one thread and read by
         * another.
         */
        private /+volatile+/ bool   closed;

        /**
         * Initial list of ServiceReferences for the tracker. This is used to
         * correctly process the initial services which could become
         * unregistered before they are tracked. This is necessary since the
         * initial set of tracked services are not "announced" by ServiceEvents
         * and therefore the ServiceEvent for unregistration could be delivered
         * before we track the service.
         *
         * A service must not be in both the initial and adding lists at the
         * same time. A service must be moved from the initial list to the
         * adding list "atomically" before we begin tracking it.
         *
         * Since the LinkedList implementation is not synchronized, all access
         * to this list must be protected by the same synchronized object for
         * thread-safety.
         *
         * @GuardedBy this
         */
        private final LinkedList    initial;

        /**
         * Tracked constructor.
         */
        protected this() {
            super();
            closed = false;
            adding = new ArrayList(6);
            initial = new LinkedList();
        }

        /**
         * Set initial list of services into tracker before ServiceEvents begin
         * to be received.
         *
         * This method must be called from ServiceTracker.open while
         * synchronized on this object in the same synchronized block as the
         * addServiceListener call.
         *
         * @param references The initial list of services to be tracked.
         * @GuardedBy this
         */
        protected void setInitialServices(ServiceReference[] references) {
            if (references is null) {
                return;
            }
            int size = references.length_;
            for (int i = 0; i < size; i++) {
                if (DEBUG) {
                    System.out_
                            .println("ServiceTracker.Tracked.setInitialServices: " + references[i]); //$NON-NLS-1$
                }
                initial.add(references[i]);
            }
        }

        /**
         * Track the initial list of services. This is called after
         * ServiceEvents can begin to be received.
         *
         * This method must be called from ServiceTracker.open while not
         * synchronized on this object after the addServiceListener call.
         *
         */
        protected void trackInitialServices() {
            while (true) {
                ServiceReference reference;
                synchronized (this) {
                    if (initial.size() is 0) {
                        /*
                         * if there are no more inital services
                         */
                        return; /* we are done */
                    }
                    /*
                     * move the first service from the initial list to the
                     * adding list within this synchronized block.
                     */
                    reference = cast(ServiceReference) initial.removeFirst();
                    if (this.get(reference) !is null) {
                        /* if we are already tracking this service */
                        if (DEBUG) {
                            System.out_
                                    .println("ServiceTracker.Tracked.trackInitialServices[already tracked]: " + reference); //$NON-NLS-1$
                        }
                        continue; /* skip this service */
                    }
                    if (adding.contains(reference)) {
                        /*
                         * if this service is already in the process of being
                         * added.
                         */
                        if (DEBUG) {
                            System.out_
                                    .println("ServiceTracker.Tracked.trackInitialServices[already adding]: " + reference); //$NON-NLS-1$
                        }
                        continue; /* skip this service */
                    }
                    adding.add(reference);
                }
                if (DEBUG) {
                    System.out_
                            .println("ServiceTracker.Tracked.trackInitialServices: " + reference); //$NON-NLS-1$
                }
                trackAdding(reference); /*
                                         * Begin tracking it. We call
                                         * trackAdding since we have already put
                                         * the reference in the adding list.
                                         */
            }
        }

        /**
         * Called by the owning <code>ServiceTracker</code> object when it is
         * closed.
         */
        protected void close() {
            closed = true;
        }

        /**
         * <code>ServiceListener</code> method for the
         * <code>ServiceTracker</code> class. This method must NOT be
         * synchronized to avoid deadlock potential.
         *
         * @param event <code>ServiceEvent</code> object from the framework.
         */
        public void serviceChanged(ServiceEvent event) {
            /*
             * Check if we had a delayed call (which could happen when we
             * close).
             */
            if (closed) {
                return;
            }
            ServiceReference reference = event.getServiceReference();
            if (DEBUG) {
                System.out_
                        .println("ServiceTracker.Tracked.serviceChanged[" + event.getType() + "]: " + reference); //$NON-NLS-1$ //$NON-NLS-2$
            }

            switch (event.getType()) {
                case ServiceEvent.REGISTERED :
                case ServiceEvent.MODIFIED :
                    if (noUserFilter) { // no user supplied filter to be checked
                        track(reference);
                        /*
                         * If the customizer throws an unchecked exception, it
                         * is safe to let it propagate
                         */
                    }
                    else { // filter supplied by user must be checked
                        if (filter.match(reference)) {
                            track(reference);
                            /*
                             * If the customizer throws an unchecked exception,
                             * it is safe to let it propagate
                             */
                        }
                        else {
                            untrack(reference);
                            /*
                             * If the customizer throws an unchecked exception,
                             * it is safe to let it propagate
                             */
                        }
                    }
                    break;
                case ServiceEvent.UNREGISTERING :
                    untrack(reference);
                    /*
                     * If the customizer throws an unchecked exception, it is
                     * safe to let it propagate
                     */
                    break;
            }
        }

        /**
         * Begin to track the referenced service.
         *
         * @param reference Reference to a service to be tracked.
         */
        private void track(ServiceReference reference) {
            Object object;
            synchronized (this) {
                object = this.get(reference);
            }
            if (object !is null) /* we are already tracking the service */
            {
                if (DEBUG) {
                    System.out_
                            .println("ServiceTracker.Tracked.track[modified]: " + reference); //$NON-NLS-1$
                }
                synchronized (this) {
                    modified(); /* increment modification count */
                }
                /* Call customizer outside of synchronized region */
                customizer.modifiedService(reference, object);
                /*
                 * If the customizer throws an unchecked exception, it is safe
                 * to let it propagate
                 */
                return;
            }
            synchronized (this) {
                if (adding.contains(reference)) { /*
                                                     * if this service is
                                                     * already in the process of
                                                     * being added.
                                                     */
                    if (DEBUG) {
                        System.out_
                                .println("ServiceTracker.Tracked.track[already adding]: " + reference); //$NON-NLS-1$
                    }
                    return;
                }
                adding.add(reference); /* mark this service is_ being added */
            }

            trackAdding(reference); /*
                                     * call trackAdding now that we have put the
                                     * reference in the adding list
                                     */
        }

        /**
         * Common logic to add a service to the tracker used by track and
         * trackInitialServices. The specified reference must have been placed
         * in the adding list before calling this method.
         *
         * @param reference Reference to a service to be tracked.
         */
        private void trackAdding(ServiceReference reference) {
            if (DEBUG) {
                System.out_
                        .println("ServiceTracker.Tracked.trackAdding: " + reference); //$NON-NLS-1$
            }
            Object object = null;
            bool becameUntracked = false;
            /* Call customizer outside of synchronized region */
            try {
                object = customizer.addingService(reference);
                /*
                 * If the customizer throws an unchecked exception, it will
                 * propagate after the finally
                 */
            }
            finally {
                synchronized (this) {
                    if (adding.remove(reference)) { /*
                                                     * if the service was not
                                                     * untracked during the
                                                     * customizer callback
                                                     */
                        if (object !is null) {
                            this.put(reference, object);
                            modified(); /* increment modification count */
                            notifyAll(); /*
                                             * notify any waiters in
                                             * waitForService
                                             */
                        }
                    }
                    else {
                        becameUntracked = true;
                    }
                }
            }
            /*
             * The service became untracked during the customizer callback.
             */
            if (becameUntracked) {
                if (DEBUG) {
                    System.out_
                            .println("ServiceTracker.Tracked.trackAdding[removed]: " + reference); //$NON-NLS-1$
                }
                /* Call customizer outside of synchronized region */
                customizer.removedService(reference, object);
                /*
                 * If the customizer throws an unchecked exception, it is safe
                 * to let it propagate
                 */
            }
        }

        /**
         * Discontinue tracking the referenced service.
         *
         * @param reference Reference to the tracked service.
         */
        protected void untrack(ServiceReference reference) {
            Object object;
            synchronized (this) {
                if (initial.remove(reference)) { /*
                                                     * if this service is
                                                     * already in the list of
                                                     * initial references to
                                                     * process
                                                     */
                    if (DEBUG) {
                        System.out_
                                .println("ServiceTracker.Tracked.untrack[removed from initial]: " + reference); //$NON-NLS-1$
                    }
                    return; /*
                             * we have removed it from the list and it will not
                             * be processed
                             */
                }

                if (adding.remove(reference)) { /*
                                                 * if the service is in the
                                                 * process of being added
                                                 */
                    if (DEBUG) {
                        System.out_
                                .println("ServiceTracker.Tracked.untrack[being added]: " + reference); //$NON-NLS-1$
                    }
                    return; /*
                             * in case the service is untracked while in the
                             * process of adding
                             */
                }
                object = this.remove(reference); /*
                                                     * must remove from tracker
                                                     * before calling customizer
                                                     * callback
                                                     */
                if (object is null) { /* are we actually tracking the service */
                    return;
                }
                modified(); /* increment modification count */
            }
            if (DEBUG) {
                System.out_
                        .println("ServiceTracker.Tracked.untrack[removed]: " + reference); //$NON-NLS-1$
            }
            /* Call customizer outside of synchronized region */
            customizer.removedService(reference, object);
            /*
             * If the customizer throws an unchecked exception, it is safe to
             * let it propagate
             */
        }
    }

    /**
     * Subclass of Tracked which implements the AllServiceListener interface.
     * This class is used by the ServiceTracker if open is called with true.
     *
     * @since 1.3
     * @ThreadSafe
     */
    class AllTracked : Tracked , AllServiceListener {
        static final long   serialVersionUID    = 4050764875305137716L;

        /**
         * AllTracked constructor.
         */
        protected this() {
            super();
        }
    }
}
