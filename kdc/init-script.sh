#!/bin/bash
echo "==================================================================================="
echo "==== Kerberos KDC and Kadmin ======================================================"
echo "==================================================================================="
KADMIN_PRINCIPAL_FULL=$KADMIN_PRINCIPAL@$REALM

echo "REALM: $REALM"
echo "KADMIN_PRINCIPAL_FULL: $KADMIN_PRINCIPAL_FULL"
echo "KADMIN_PASSWORD: $KADMIN_PASSWORD"
echo ""

mkdir -p /var/log/kerberos

echo "==================================================================================="
echo "==== /etc/krb5.conf ==============================================================="
echo "==================================================================================="
KDC_KADMIN_SERVER=$(hostname -f)
tee /etc/krb5.conf <<EOF
[libdefaults]

default_realm     = $REALM
forwardable       = true
rdns              = false
dns_lookup_kdc    = no
dns_lookup_realm  = no

[realms]
	$REALM = {
		kdc_ports = 88,750
		kadmind_port = 749
		kdc = $KDC_KADMIN_SERVER
		admin_server = $KDC_KADMIN_SERVER
	}

[domain_realm]
.$DOMAIN = $REALM
$DOMAIN = $REALM
EOF
echo ""

echo "==================================================================================="
echo "==== /etc/krb5kdc/kdc.conf ========================================================"
echo "==================================================================================="
tee /etc/krb5kdc/kdc.conf <<EOF
[libdefaults]

default_realm     = $REALM
forwardable       = true
rdns              = false
dns_lookup_kdc    = no
dns_lookup_realm  = no

[realms]
	$REALM = {
		acl_file = /etc/krb5kdc/kadm5.acl
		max_renewable_life = 7d 0h 0m 0s
		supported_enctypes = $SUPPORTED_ENCRYPTION_TYPES
		default_principal_flags = +preauth
	}

[domain_realm]
.$DOMAIN = $REALM
$DOMAIN = $REALM

[logging]
kdc = STDERR
admin_server = STDERR
default = STDERR
EOF
echo ""

echo "==================================================================================="
echo "==== /etc/krb5kdc/kadm5.acl ======================================================="
echo "==================================================================================="
tee /etc/krb5kdc/kadm5.acl <<EOF
$KADMIN_PRINCIPAL_FULL *
noPermissions@$REALM X
EOF
echo ""

echo "==================================================================================="
echo "==== Creating realm ==============================================================="
echo "==================================================================================="
MASTER_PASSWORD=$(tr -cd '[:alnum:]' < /dev/urandom | fold -w30 | head -n1)
# This command also starts the krb5-kdc and krb5-admin-server services
krb5_newrealm <<EOF
$MASTER_PASSWORD
$MASTER_PASSWORD
EOF
echo ""

echo "==================================================================================="
echo "==== Create the principals in the acl ============================================="
echo "==================================================================================="
echo "Adding $KADMIN_PRINCIPAL principal"
kadmin.local -q "delete_principal -force $KADMIN_PRINCIPAL_FULL"
echo ""
kadmin.local -q "addprinc -pw $KADMIN_PASSWORD $KADMIN_PRINCIPAL_FULL"
echo ""

echo "Adding noPermissions principal"
kadmin.local -q "delete_principal -force noPermissions@$REALM"
echo ""
kadmin.local -q "addprinc -pw $KADMIN_PASSWORD noPermissions@$REALM"
echo ""

echo "==================================================================================="
echo "==== Create the principals ============================================="
echo "==================================================================================="
echo "Clearing keytab directory - $KEYTAB_DIR"
echo "Entries:"
ls -1 $KEYTAB_DIR
rm -rf $KEYTAB_DIR/*
echo ""

echo "Adding service principal - $SERVICE_PRINCIPAL"
kadmin.local -q "addprinc -randkey $SERVICE_PRINCIPAL.$DOMAIN@$REALM"
echo ""

echo "Modifying service principal"
kadmin.local -q "modprinc -maxrenewlife 24h -maxlife 24h +allow_renewable $SERVICE_PRINCIPAL.$DOMAIN@$REALM"
echo ""

echo "Exporting service.keytab"
kadmin.local -q "ktadd  -k $KEYTAB_DIR/service.keytab -e \"$SUPPORTED_ENCRYPTION_TYPES\" $SERVICE_PRINCIPAL.$DOMAIN@$REALM "
echo ""

echo "Adding client principal - $CLIENT_PRINCIPAL"
kadmin.local -q "addprinc -randkey $CLIENT_PRINCIPAL@$REALM"
echo ""

echo "Modifying client principal"
kadmin.local -q "modprinc -maxrenewlife 24h -maxlife 24h +allow_renewable $CLIENT_PRINCIPAL@$REALM"
echo ""

echo "Exporting client.keytab"
kadmin.local -q "ktadd  -k $KEYTAB_DIR/client.keytab -e \"$SUPPORTED_ENCRYPTION_TYPES\" $CLIENT_PRINCIPAL@$REALM "

chmod 660 $KEYTAB_DIR/service.keytab
chmod 660 $KEYTAB_DIR/client.keytab

echo "==================================================================================="
echo "==== Run the services ============================================================="
echo "==================================================================================="
# We want the container to keep running until we explicitly kill it.
# So the last command cannot immediately exit. See
#   https://docs.docker.com/engine/reference/run/#detached-vs-foreground
# for a better explanation.

krb5kdc
kadmind -nofork
