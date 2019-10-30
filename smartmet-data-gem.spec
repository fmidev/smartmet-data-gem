%define smartmetroot /smartmet

Name:           smartmet-data-gem
Version:        19.10.30
Release:        1%{?dist}.fmi
Summary:        SmartMet Data GEM
Group:          System Environment/Base
License:        MIT
URL:            https://github.com/fmidev/smartmet-data-gem
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
BuildArch:	noarch

%{?el6:Requires: smartmet-qdconversion}
%{?el7:Requires: smartmet-qdtools}
Requires:       curl
Requires:	lbzip2


%description
SmartMet data ingest module for Canadian GEM numerical weather model.

%prep

%build

%pre

%install
rm -rf $RPM_BUILD_ROOT
mkdir $RPM_BUILD_ROOT
cd $RPM_BUILD_ROOT

mkdir -p .%{smartmetroot}/cnf/cron/{cron.d,cron.hourly}
mkdir -p .%{smartmetroot}/cnf/data
mkdir -p .%{smartmetroot}/tmp/data/gem
mkdir -p .%{smartmetroot}/logs/data
mkdir -p .%{smartmetroot}/run/data/gem/{bin,cnf}

cat > %{buildroot}%{smartmetroot}/cnf/cron/cron.d/gem.cron <<EOF
# Available after 0400 and 1600 UTC
10 * * * * utcrun 4  /smartmet/run/data/gem/bin/get_gem.sh 
10 * * * * utcrun 16 /smartmet/run/data/gem/bin/get_gem.sh 
EOF

cat > %{buildroot}%{smartmetroot}/cnf/cron/cron.hourly/clean_data_gem <<EOF
#!/bin/sh
# Clean GEM data
cleaner -maxfiles 4 '_gem_.*_surface.sqd' %{smartmetroot}/data/gem
cleaner -maxfiles 4 '_gem_.*_pressure.sqd' %{smartmetroot}/data/gem
cleaner -maxfiles 4 '_gem_.*_surface.sqd' %{smartmetroot}/editor/in
cleaner -maxfiles 4 '_gem_.*_pressure.sqd' %{smartmetroot}/editor/in
EOF

cat > %{buildroot}%{smartmetroot}/cnf/data/gem.cnf <<EOF
AREA="caribbean"

TOP=40
BOTTOM=-10
LEFT=-120
RIGHT=0

LEG1_START=0
LEG1_STEP=3
LEG1_END=120

LEG2_START=126
LEG2_STEP=6
LEG2_END=168

GRIBTOQD_ARGS=""
#GRIB_COPY_DEST=
EOF

install -m 755 %_topdir/SOURCES/smartmet-data-gem/get_gem.sh %{buildroot}%{smartmetroot}/run/data/gem/bin/

%post

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,smartmet,smartmet,-)
%config(noreplace) %{smartmetroot}/cnf/data/gem.cnf
%config(noreplace) %{smartmetroot}/cnf/cron/cron.d/gem.cron
%config(noreplace) %attr(0755,smartmet,smartmet) %{smartmetroot}/cnf/cron/cron.hourly/clean_data_gem
%{smartmetroot}/*

%changelog
* Wed Oct 15 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 19.10.30-1%{?dist}.fmi
- http -> https
* Fri Dec 15 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.12.15-1%{?dist}.fmi
- rsync now creates flagfile when download is complete
* Thu Dec 7 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.12.7-1%{?dist}.fmi
- rsync now creates subdirectory for each model run
* Thu Nov 16 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.11.16-1.el7.fmi
- Improved logging and grib file testing
* Thu Jul 6 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.7.6-1.el7.fmi
- Updated script to log stdout if run from terminal
* Wed Apr 19 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.1.19-1.el6.fmi
- Updated file names
* Wed Jan 18 2017 Mikko Rauhala <mikko.rauhala@fmi.fi> 17.1.18-1.el6.fmi
- Updated dependencies
* Wed Jun 3 2015 Santeri Oksman <santeri.oksman@fmi.fi> 15.6.3-1.el7.fmi
- RHEL 7 version
* Fri Aug 8 2013 Mikko Rauhala <mikko.rauhala@fmi.fi> 13.8.8-1.el6.fmi
- Initial build 1.0.0
