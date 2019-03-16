
Get-Module Pester.Runtime, Pester.Utility, P, Pester, Axiom, Stack | Remove-Module

Import-Module $PSScriptRoot\p.psm1 -DisableNameChecking
Import-Module $PSScriptRoot\..\Dependencies\Axiom\Axiom.psm1 -DisableNameChecking

Import-Module $PSScriptRoot\..\Pester.psd1

$global:PesterDebugPreference = @{
    ShowFullErrors         = $true
    WriteDebugMessages     = $false
    WriteDebugMessagesFrom = "Mock"
}


i {
    b "basic mocking in RSpec Pester" {
        t "running a single mock in one It" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    It 'i1' {
                        Mock f { "mock" }
                        f
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].StandardOutput | Verify-Equal "mock"
        }

        t "mock does not leak into the subsequent It" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    It 'i1' {
                        Mock f { "mock" }
                        f
                    }

                    It 'i2' {
                        f
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].StandardOutput | Verify-Equal "mock"
            $actual.Blocks[0].Tests[1].StandardOutput | Verify-Equal "real"
        }

        t "mock defined in beforeall is used in every it" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    BeforeAll {
                        Mock f { "mock" }
                    }

                    It 'i1' {
                        f
                    }

                    It 'i2' {
                        f
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].StandardOutput | Verify-Equal "mock"
            $actual.Blocks[0].Tests[1].StandardOutput | Verify-Equal "mock"
        }


        t "mock defined in beforeall is counted independently" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    BeforeAll {
                        Mock f { "mock" }
                    }

                    It 'i1' {
                        f
                        Assert-MockCalled f -Times 1 -Exactly
                    }

                    It 'i2' {
                        f
                        Assert-MockCalled f -Times 1 -Exactly
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].Passed | Verify-True
            $actual.Blocks[0].Tests[1].Passed | Verify-True
        }

        t "mock defined in before all can be counted from all tests with -Describe" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    BeforeAll {
                        Mock f { "mock" }
                    }

                    It 'i1' {
                        f
                        Assert-MockCalled f -Times 1 -Exactly
                    }

                    It 'i2' {
                        f
                        Assert-MockCalled f -Times 2 -Exactly -Scope Describe
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].Passed | Verify-True
            $actual.Blocks[0].Tests[1].Passed | Verify-True
        }

        t "mock defined in before all can and counted from after all automatically counts all calls in the current block" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    BeforeAll {
                        Mock f { "mock" }
                    }

                    It 'i1' {
                        f
                    }

                    It 'i2' {
                        f
                    }

                    AfterAll {
                        Assert-MockCalled f -Times 2 -Exactly
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].Passed | Verify-True
            $actual.Blocks[0].Tests[1].Passed | Verify-True
        }
    }

    b "taking mocks from all scopes" {
        t "mocks defined in the parent scope can still be used" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    BeforeAll {
                        Mock f { "mock" }
                    }

                    Describe 'd2' {
                        Describe 'd3' {
                            It 'i1' {
                                f
                            }
                        }
                    }

                    AfterAll {
                        Assert-MockCalled f -Times 1 -Exactly
                    }
                }
            } -PassThru

            $actual.Blocks[0].Blocks[0].Blocks[0].Tests[0].StandardOutput | Verify-Equal 'mock'
        }
    }

    b "mock filters" {
        t "calling filtered and default mock chooses the correct mock to call" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function f { "real" } }
                Describe 'd1' {
                    BeforeAll {
                        Mock Get-Variable { "filtered" } -ParameterFilter {
                            $Name -eq 'PSVersionTable' -and $ValueOnly
                        }

                        Mock Get-Variable { "default" }
                    }

                    It 'makes a call to the filtered mock' {
                        Get-Variable -Name PSVersionTable -ValueOnly | Should -Be "filtered"
                    }

                    It 'makes a call to the default mock' {
                        Get-Variable -Name PSVersionTable | Should -Be "default"
                    }
                }
            } -PassThru

            $actual.Blocks[0].Tests[0].Passed | Verify-True
            $actual.Blocks[0].Tests[1].Passed | Verify-True
        }
    }

    b "named mock scopes" {
        t "asserting in scope describe finds all mocks in the nearest describe" {
            $actual = Invoke-Pester -ScriptBlock {
                Add-Dependency { function a { } }
                Describe 'd-2' {
                    # scope 4
                    Describe "d-1" {
                        # scope 3
                        Describe 'd1' {
                            # scope 2
                            BeforeAll {
                                Mock a {}
                            }

                            It 'i1' {
                                a # call 1
                            }

                            Context "c1" {
                                # scope 1
                                It 'i2' {
                                    a # call 2
                                }

                                It 'i1' {
                                    # scope 0
                                    Assert-MockCalled a -Exactly 0 -Scope 0
                                    Assert-MockCalled a -Exactly 0 -Scope It
                                    Assert-MockCalled a -Exactly 1 -Scope 1
                                    Assert-MockCalled a -Exactly 1 -Scope Context
                                    Assert-MockCalled a -Exactly 2 -Scope 2
                                    Assert-MockCalled a -Exactly 2 -Scope Describe
                                    Assert-MockCalled a -Exactly 2 -Scope 3
                                    Assert-MockCalled a -Exactly 2 -Scope 4
                                }
                            }
                        }
                    }
                }
            } -PassThru

            $actual.Blocks[0].Blocks[0].Blocks[0].Blocks[0].Tests[1].Passed | Verify-True
        }


    }

    b "Running generated tests" {
        t "generating simple tests from foreach with external Id" {
            $result = Invoke-Pester -ScriptBlock {
                Describe "d1" {
                    foreach ($id in 1..10) {
                        It "it${id}" { $true } -AutomationId $id
                    }
                }
            } -PassThru

            $result.Blocks[0].ErrorRecord | Verify-Null
            $result.Blocks[0].Tests.Count | Verify-Equal 10
            $result.Blocks[0].Tests[0].Passed | Verify-True
        }

        t "generating parametrized tests from foreach with external id" {
            $result = Invoke-Pester -ScriptBlock {
                Describe "d1" {
                    foreach ($id in 1..10) {
                        It "it$id-<value>" -TestCases @(
                            @{ Value = 1}
                            @{ Value = 2}
                            @{ Value = 3}
                        ) {
                            $true
                        } -AutomationId $id
                    }
                }
            } -PassThru

            $result.Blocks[0].ErrorRecord | Verify-Null
            $result.Blocks[0].Tests.Count | Verify-Equal 30
            $result.Blocks[0].Tests[0].Passed | Verify-True
        }

        t "generating simple tests from foreach without external Id" {
            $result = Invoke-Pester -ScriptBlock {
                Describe "d1" {
                    foreach ($id in 1..10) {
                        It "it$id" { $true }
                    }
                }
            } -PassThru

            $result.Blocks[0].ErrorRecord | Verify-Null
            $result.Blocks[0].Tests.Count | Verify-Equal 10
            $result.Blocks[0].Tests[0].Passed | Verify-True
        }

        t "generating parametrized tests from foreach without external id" {
            $result = Invoke-Pester -ScriptBlock {
                Describe "d1" {
                    foreach ($id in 1..10) {
                        It "it-$id-<value>" -TestCases @(
                            @{ Value = 1}
                            @{ Value = 2}
                            @{ Value = 3}
                        ) {
                            $true
                        }
                    }
                }
            } -PassThru

            $result.Blocks[0].ErrorRecord | Verify-Null
            $result.Blocks[0].Tests.Count | Verify-Equal 30
            $result.Blocks[0].Tests[0].Passed | Verify-True
        }

        t "generating multiple parametrized tests from foreach without external id" {
            $result = Invoke-Pester -ScriptBlock {
                Describe "d1" {
                    foreach ($id in 1..10) {
                        It "first-it-$id-<value>" -TestCases @(
                            @{ Value = 1}
                            @{ Value = 2}
                            @{ Value = 3}
                        ) {
                            $true
                        }

                        It "second-it-$id-<value>" -TestCases @(
                            @{ Value = 1}
                            @{ Value = 2}
                            @{ Value = 3}
                        ) {
                            $true
                        }
                    }
                }
            } -PassThru

            $result.Blocks[0].ErrorRecord | Verify-Null
            $result.Blocks[0].Tests.Count | Verify-Equal 60
            $result.Blocks[0].Tests[0].Passed | Verify-True
        }

        t "generating multiple parametrized tests from foreach with external id" {
            $result = Invoke-Pester -ScriptBlock {
                Describe "d1" {
                    foreach ($id in 1..10) {
                        It "first-it-$id-<value>" -TestCases @(
                            @{ Value = 1}
                            @{ Value = 2}
                            @{ Value = 3}
                        ) {
                            $true
                        } -AutomationId $Id

                        It "second-it-$id-<value>" -TestCases @(
                            @{ Value = 1}
                            @{ Value = 2}
                            @{ Value = 3}
                        ) {
                            $true
                        } -AutomationId $id
                    }
                }
            } -PassThru

            $result.Blocks[0].ErrorRecord | Verify-Null
            $result.Blocks[0].Tests.Count | Verify-Equal 60
            $result.Blocks[0].Tests[0].Passed | Verify-True
        }
    }

    b "Add-Dependency paths" {
        t "`$PSScriptRoot in Add-Dependency has the same value as in the script that calls it" {
            $container = [PSCustomObject]@{
                InScript = $null
                InAddDependency = $null
            }
            $result = Invoke-Pester -ScriptBlock {
                $container.InScript = $PSScriptRoot
                Add-Dependency {
                     $container.InAddDependency = $PSScriptRoot
                }

                Describe "a" {
                    It "b" {
                        # otherwise the container would not run
                        $true
                    }
                }
            } -PassThru

            $container.InAddDependency | Verify-Equal $container.InScript
        }
    }

}
