/*
 * $Header: /cvshome/build/org.osgi.framework/src/org/osgi/framework/BundleListener.java,v 1.13 2007/02/21 16:49:05 hargrave Exp $
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
module org.osgi.framework.BundleListener;

import java.lang.all;

import org.osgi.framework.BundleEvent; // packageimport

import java.util.EventListener;

/**
 * A <code>BundleEvent</code> listener. <code>BundleListener</code> is a
 * listener interface that may be implemented by a bundle developer. When a
 * <code>BundleEvent</code> is fired, it is asynchronously delivered to a
 * <code>BundleListener</code>. The Framework delivers
 * <code>BundleEvent</code> objects to a <code>BundleListener</code> in
 * order and must not concurrently call a <code>BundleListener</code>.
 * <p>
 * A <code>BundleListener</code> object is registered with the Framework using
 * the {@link BundleContext#addBundleListener} method.
 * <code>BundleListener</code>s are called with a <code>BundleEvent</code>
 * object when a bundle has been installed, resolved, started, stopped, updated,
 * unresolved, or uninstalled.
 *
 * @see BundleEvent
 * @NotThreadSafe
 * @version $Revision: 1.13 $
 */

public interface BundleListener : EventListener {
    /**
     * Receives notification that a bundle has had a lifecycle change.
     *
     * @param event The <code>BundleEvent</code>.
     */
    public void bundleChanged(BundleEvent event);
}
