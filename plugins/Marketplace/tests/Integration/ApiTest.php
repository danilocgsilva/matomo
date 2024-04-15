<?php
/**
 * Matomo - free/libre analytics platform
 *
 * @link https://matomo.org
 * @license http://www.gnu.org/licenses/gpl-3.0.html GPL v3 or later
 */

namespace Piwik\Plugins\Marketplace\tests\Integration;

use Exception;
use Piwik\Container\StaticContainer;
use Piwik\Plugins\Marketplace\API;
use Piwik\Plugins\Marketplace\LicenseKey;
use Piwik\Plugins\Marketplace\tests\Framework\Mock\Service;
use Piwik\Plugins\UsersManager\SystemSettings;
use Piwik\Tests\Framework\Fixture;
use Piwik\Tests\Framework\Mock\FakeAccess;
use Piwik\Tests\Framework\TestCase\IntegrationTestCase;
use Piwik\Plugins\Marketplace\Api\Service\Exception as ServiceException;

/**
 * @group Marketplace
 * @group ApiTest
 * @group Api
 * @group Plugins
 */
class ApiTest extends IntegrationTestCase
{
    /**
     * @var API
     */
    private $api;

    /**
     * @var Service
     */
    private $service;

    public function setUp(): void
    {
        parent::setUp();

        API::unsetInstance();
        $this->api = API::getInstance();

        Fixture::createSuperUser();
        if (!Fixture::siteCreated(1)) {
            Fixture::createWebsite('2012-01-01 00:00:00');
        }

        $this->setSuperUser();
    }

    public function test_createAccount_shouldSucceedIfMarketplaceCallsDidNotFail(): void
    {
        $this->assertNotHasLicenseKey();

        $this->service->setOnDownloadCallback(static function ($action, $params, $postData) {
            self::assertSame('createAccount', $action);
            self::assertArrayHasKey('email', $postData);
            self::assertSame('test@matomo.org', $postData['email']);

            return [
                'status' => 200,
                'headers' => [],
                'data' => json_encode(['license_key' => 'key'])
            ];
        });

        self::assertTrue($this->api->createAccount('test@matomo.org'));

        $this->assertHasLicenseKey();
    }

    public function test_createAccount_requiresSuperUserAccess_IfUser()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setUser();
        $this->api->createAccount('test@matomo.org');
    }

    public function test_createAccount_requiresSuperUserAccess_IfAnonymous(): void
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setAnonymousUser();
        $this->api->createAccount('test@matomo.org');
    }

    public function test_createAccount_shouldThrowException_ifLicenseKeyIsAlreadySet(): void
    {
        $this->buildLicenseKey()->set('key');

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Marketplace_CreateAccountErrorLicenseExists');

        $this->api->createAccount('test@matomo.org');
    }

    public function test_createAccount_shouldThrowException_ifEmailIsEmpty(): void
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('General_ValidatorErrorEmptyValue');

        $this->api->createAccount('');
    }

    public function test_createAccount_shouldThrowException_ifEmailIsInvalid(): void
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Marketplace_CreateAccountErrorEmailInvalid');

        $this->api->createAccount('invalid.email@');
    }

    public function test_createAccount_shouldThrowException_ifEmailIsNotAllowed(): void
    {
        $settings = StaticContainer::get(SystemSettings::class);
        $settings->allowedEmailDomains->setValue(['example.org']);

        $this->expectException(Exception::class);
        $this->expectExceptionMessage('UsersManager_ErrorEmailDomainNotAllowed');

        $this->api->createAccount('test@matomo.org');
    }

    /**
     * @dataProvider dataCreateAccountErrorDownloadResponses
     */
    public function test_createAccount_shouldThrowException_ifSomethingGoesWrong(
        array $responseInfo,
        string $expectedException,
        string $expectedExceptionMessage
    ): void {
        $this->expectException($expectedException);
        $this->expectExceptionMessage($expectedExceptionMessage);

        $this->service->setOnDownloadCallback(static function () use ($responseInfo) {
            return $responseInfo;
        });

        $this->api->createAccount('test@matomo.org');
    }

    public function dataCreateAccountErrorDownloadResponses(): iterable
    {
        yield 'marketplace response not readable' => [
            [
                'status' => 500,
                'headers' => [],
                'data' => 'not valid json',
            ],
            Exception::class,
            'Marketplace_CreateAccountErrorAPI',
        ];

        yield 'marketplace rejected email as invalid' => [
            [
                'status' => 400,
                'headers' => [],
                'data' => '',
            ],
            Exception::class,
            'Marketplace_CreateAccountErrorAPIEmailInvalid',
        ];

        yield 'marketplace rejected email as duplicate' => [
            [
                'status' => 409,
                'headers' => [],
                'data' => '',
            ],
            Exception::class,
            'Marketplace_CreateAccountErrorAPIEmailExists',
        ];

        yield 'unexpected response status code' => [
            [
                'status' => 204,
                'headers' => [],
                'data' => '',
            ],
            Exception::class,
            'Marketplace_CreateAccountErrorAPI',
        ];

        yield 'missing license key' => [
            [
                'status' => 200,
                'headers' => [],
                'data' => '',
            ],
            Exception::class,
            'Marketplace_CreateAccountErrorAPI',
        ];
    }

    public function test_deleteLicenseKey_requiresSuperUserAccess_IfUser()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setUser();
        $this->api->deleteLicenseKey();
    }

    public function test_deleteLicenseKey_requiresSuperUserAccess_IfAnonymous()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setAnonymousUser();
        $this->api->deleteLicenseKey();
    }

    public function test_deleteLicenseKey_shouldRemoveAnExistingKey()
    {
        $this->buildLicenseKey()->set('key');
        $this->assertHasLicenseKey();

        $this->api->deleteLicenseKey();

        $this->assertNotHasLicenseKey();
    }

    public function test_saveLicenseKey_requiresSuperUserAccess_IfUser()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setUser();
        $this->api->saveLicenseKey('key');
    }

    public function test_saveLicenseKey_requiresSuperUserAccess_IfAnonymous()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setAnonymousUser();
        $this->api->saveLicenseKey('key');
    }

    public function test_saveLicenseKey_shouldThrowException_IfTokenIsNotValid()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Marketplace_ExceptionLinceseKeyIsNotValid');

        $this->service->returnFixture('v2.0_consumer_validate-access_token-notexistingtoken.json');
        $this->api->saveLicenseKey('key');
    }

    public function test_saveLicenseKey_shouldCallTheApiTheCorrectWay()
    {
        $this->service->returnFixture('v2.0_consumer-access_token-valid_but_expired.json');

        try {
            $this->api->saveLicenseKey('key123');
        } catch (Exception $e) {
        }

        // make sure calls API the correct way
        $this->assertSame('consumer/validate', $this->service->action);
        $this->assertSame(array(), $this->service->params);
        $this->assertSame('key123', $this->service->getAccessToken());
        $this->assertNotHasLicenseKey();
    }

    public function test_saveLicenseKey_shouldActuallySaveToken_IfValid()
    {
        $this->service->returnFixture('v2.0_consumer_validate-access_token-consumer1_paid2_custom1.json');
        $success = $this->api->saveLicenseKey('123licensekey');
        $this->assertTrue($success);

        $this->assertHasLicenseKey();
        $this->assertSame('123licensekey', $this->buildLicenseKey()->get());
    }

    public function test_saveLicenseKey_shouldThrowException_IfConnectionToMarketplaceFailed()
    {
        $this->expectException(ServiceException::class);
        $this->expectExceptionMessage('Host not reachable');

        $this->service->throwException(new ServiceException('Host not reachable', ServiceException::HTTP_ERROR));
        $this->api->saveLicenseKey('123licensekey');
    }

    public function test_startFreeTrial_requiresSuperUserAccess_IfUser()
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setUser();
        $this->api->startFreeTrial('testPlugin');
    }

    public function test_startFreeTrial_requiresSuperUserAccess_IfAnonymous(): void
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('checkUserHasSuperUserAccess');

        $this->setAnonymousUser();
        $this->api->startFreeTrial('testPlugin');
    }

    public function test_startFreeTrial_requiresValidPluginName(): void
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Invalid plugin name given');

        $this->api->startFreeTrial('this/is/not/valid');
    }

    public function test_startFreeTrial_shouldThrowException_ifMarketplaceRequestEncountersHttpError(): void
    {
        $this->expectException(Exception::class);
        $this->expectExceptionMessage('Host not reachable');

        $this->service->throwException(new ServiceException('Host not reachable', ServiceException::HTTP_ERROR));
        $this->api->startFreeTrial('testPlugin');
    }

    public function test_startFreeTrial_shouldSucceedIfMarketplaceCallsDidNotFail(): void
    {
        $pluginName = 'testPlugin';
        $expectedAction = 'plugins/' . $pluginName . '/freeTrial';

        $this->service->setOnDownloadCallback(static function ($action) use ($expectedAction) {
            self::assertSame($expectedAction, $action);

            return [
                'status' => 201,
                'headers' => [],
                'data' => ''
            ];
        });

        self::assertTrue($this->api->startFreeTrial($pluginName));
    }

    /**
     * @dataProvider dataStartFreeTrialErrorDownloadResponses
     */
    public function test_startFreeTrial_shouldThrowException_ifSomethingGoesWrong(
        array $responseInfo,
        string $expectedException,
        string $expectedExceptionMessage
    ): void {
        $this->expectException($expectedException);
        $this->expectExceptionMessage($expectedExceptionMessage);

        $this->service->setOnDownloadCallback(static function () use ($responseInfo) {
            return $responseInfo;
        });

        $this->api->startFreeTrial('testPlugin');
    }

    public function dataStartFreeTrialErrorDownloadResponses(): iterable
    {
        yield 'marketplace response not readable' => [
            [
                'status' => 500,
                'headers' => [],
                'data' => 'not valid json',
            ],
            ServiceException::class,
            'There was an error reading the response from the Marketplace. Please try again later.',
        ];

        yield 'error in marketplace response' => [
            [
                'status' => 400,
                'headers' => [],
                'data' => json_encode(['error' => 'something went wrong']),
            ],
            Exception::class,
            'Marketplace_TrialStartErrorAPI',
        ];

        yield 'unexpected response status code' => [
            [
                'status' => 200,
                'headers' => [],
                'data' => '',
            ],
            Exception::class,
            'Marketplace_TrialStartErrorAPI',
        ];

        yield 'unexpected response content string' => [
            [
                'status' => 201,
                'headers' => [],
                'data' => json_encode('operation successful'),
            ],
            Exception::class,
            'Marketplace_TrialStartErrorAPI',
        ];

        yield 'unexpected response content array' => [
            [
                'status' => 201,
                'headers' => [],
                'data' => json_encode(['success' => true]),
            ],
            Exception::class,
            'Marketplace_TrialStartErrorAPI',
        ];
    }

    public function provideContainerConfig()
    {
        $this->service = new Service();

        return array(
            'Piwik\Access' => new FakeAccess(),
            'Piwik\Plugins\Marketplace\Api\Service' => $this->service
        );
    }

    protected function setSuperUser()
    {
        FakeAccess::clearAccess(true);
    }

    protected function setUser()
    {
        FakeAccess::clearAccess(false);
        FakeAccess::$idSitesView = array(1);
        FakeAccess::$idSitesAdmin = array();
        FakeAccess::$identity = 'aUser';
    }

    protected function setAnonymousUser()
    {
        FakeAccess::clearAccess();
        FakeAccess::$identity = 'anonymous';
    }

    protected function buildLicenseKey()
    {
        return new LicenseKey();
    }

    private function assertHasLicenseKey()
    {
        $this->assertTrue($this->buildLicenseKey()->has());
    }

    private function assertNotHasLicenseKey()
    {
        $this->assertFalse($this->buildLicenseKey()->has());
    }
}
