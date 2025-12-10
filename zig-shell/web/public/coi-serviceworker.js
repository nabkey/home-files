/*! coi-serviceworker v0.1.7 - Guido Zuidhof and contributors, licensed under MIT */
/*
 * This service worker enables SharedArrayBuffer on static hosts by
 * injecting the required Cross-Origin headers.
 *
 * Source: https://github.com/nicktaras/coi-serviceworker
 */
let coepCredentialless = false;
if (typeof window === "undefined") {
  self.addEventListener("install", () => self.skipWaiting());
  self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

  self.addEventListener("message", (ev) => {
    if (!ev.data) {
      return;
    } else if (ev.data.type === "deregister") {
      self.registration
        .unregister()
        .then(() => {
          return self.clients.matchAll();
        })
        .then((clients) => {
          clients.forEach((client) => client.navigate(client.url));
        });
    } else if (ev.data.type === "coepCredentialless") {
      coepCredentialless = ev.data.value;
    }
  });

  self.addEventListener("fetch", function (event) {
    const r = event.request;
    if (r.cache === "only-if-cached" && r.mode !== "same-origin") {
      return;
    }

    const request =
      coepCredentialless && r.mode === "no-cors"
        ? new Request(r, {
            credentials: "omit",
          })
        : r;

    event.respondWith(
      fetch(request)
        .then((response) => {
          if (response.status === 0) {
            return response;
          }

          const newHeaders = new Headers(response.headers);
          newHeaders.set("Cross-Origin-Embedder-Policy",
            coepCredentialless ? "credentialless" : "require-corp"
          );
          newHeaders.set("Cross-Origin-Opener-Policy", "same-origin");

          return new Response(response.body, {
            status: response.status,
            statusText: response.statusText,
            headers: newHeaders,
          });
        })
        .catch((e) => console.error(e))
    );
  });
} else {
  (() => {
    const reloadedByCOI = window.sessionStorage.getItem("coiReloadedByCOI");
    window.sessionStorage.removeItem("coiReloadedByCOI");

    const coepDegrading = reloadedByCOI === "coepdegrade";

    // You can customize the behavior with these options:
    const coi = {
      shouldRegister: () => !reloadedByCOI,
      shouldDeregister: () => false,
      coepCredentialless: () => true,
      coepDegrade: () => true,
      doReload: () => window.location.reload(),
      quiet: false,
    };

    // Check for custom options
    if (window.coi) {
      Object.assign(coi, window.coi);
    }

    const n = navigator;
    const controlling = n.serviceWorker && n.serviceWorker.controller;

    // Check if cross-origin isolated
    if (window.crossOriginIsolated !== false || controlling) {
      if (!coi.quiet) {
        console.log(
          controlling
            ? "coi-serviceworker: already controlling"
            : "coi-serviceworker: crossOriginIsolated"
        );
      }
      return;
    }

    if (!coi.shouldRegister()) {
      if (!coi.quiet) {
        console.log("coi-serviceworker: registration skipped");
      }
      return;
    }

    if (coi.shouldDeregister()) {
      if (n.serviceWorker) {
        n.serviceWorker.getRegistrations().then((registrations) => {
          registrations.forEach((r) => r.unregister());
        });
      }
      return;
    }

    // Currently fixing this with workers is not supported
    if (n.serviceWorker === undefined) {
      console.error(
        "coi-serviceworker: serviceWorker not available in this context"
      );
      return;
    }

    // Register the service worker
    n.serviceWorker
      .register(window.document.currentScript.src)
      .then((registration) => {
        if (!coi.quiet) {
          console.log("coi-serviceworker: registered", registration.scope);
        }

        registration.addEventListener("updatefound", () => {
          if (!coi.quiet) {
            console.log("coi-serviceworker: update found");
          }
        });

        // If coepCredentialless is supported, use it
        if (coi.coepCredentialless()) {
          if (registration.active) {
            registration.active.postMessage({
              type: "coepCredentialless",
              value: true,
            });
          }
        }

        // Check for waiting/installing workers
        if (registration.waiting || registration.installing) {
          const worker = registration.waiting || registration.installing;
          if (worker) {
            worker.addEventListener("statechange", () => {
              if (worker.state === "activated") {
                if (!coi.quiet) {
                  console.log("coi-serviceworker: activated, reloading");
                }
                window.sessionStorage.setItem("coiReloadedByCOI", "true");
                coi.doReload();
              }
            });
          }
        } else if (registration.active) {
          if (!coi.quiet) {
            console.log("coi-serviceworker: active, reloading");
          }
          window.sessionStorage.setItem("coiReloadedByCOI", "true");
          coi.doReload();
        }
      })
      .catch((error) => {
        console.error("coi-serviceworker: registration failed", error);
      });
  })();
}
