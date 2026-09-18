#!/bin/sh
set -eu
# Run as the desktop user. No broad --talk rules: only queries and signals.
set -- unix:path=/run/dbus/system_bus_socket "$1" --filter
for service in org.freedesktop.NetworkManager org.bluez org.freedesktop.UPower net.hadess.PowerProfiles org.freedesktop.UPower.PowerProfiles; do
  set -- "$@" "--see=$service" \
    "--call=$service=org.freedesktop.DBus.Properties.Get" \
    "--call=$service=org.freedesktop.DBus.Properties.GetAll" \
    "--call=$service=org.freedesktop.DBus.ObjectManager.GetManagedObjects" \
    "--call=$service=org.freedesktop.DBus.Introspectable.Introspect" \
    "--broadcast=$service=org.freedesktop.DBus.Properties.PropertiesChanged" \
    "--broadcast=$service=org.freedesktop.DBus.ObjectManager.*"
done
set -- "$@" \
  --call=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.GetDevices \
  --call=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.GetAllDevices \
  --call=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.GetPermissions \
  --call=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.Device.Wireless.GetAccessPoints \
  --call=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.Device.Wireless.GetAllAccessPoints \
  --call=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.Settings.Connection.GetSettings \
  --broadcast=org.freedesktop.NetworkManager=org.freedesktop.NetworkManager.* \
  --call=org.freedesktop.UPower=org.freedesktop.UPower.EnumerateDevices \
  --call=org.freedesktop.UPower=org.freedesktop.UPower.GetDisplayDevice
exec xdg-dbus-proxy "$@"
