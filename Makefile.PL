use inc::Module::Install;

name           'Newts';
all_from       'lib/Newts.pm';

requires       'AnyEvent::HTTP'  => '0.0';
requires       'URI'  => '0.0';
requires       'JSON'  => '0.0';
requires       'Math::BigInt'  => '0.0';
requires       'HTTP::Headers'  => '0.0';
recommends     'Math::BigInt::GMP' => '0.0';

test_requires q(Test::Most) => 0.25;
test_requires q(AnyEvent) => 0.0;
test_requires q(EV) => 0.0;
bugtracker q(https://github.com/rfdrake/p5-Newts/issues);
homepage q(http://search.cpan.org/dist/Newts);
repository q(git://github.com/rfdrake/p5-Newts.git);
license 'perl';

auto_install;
WriteAll;

