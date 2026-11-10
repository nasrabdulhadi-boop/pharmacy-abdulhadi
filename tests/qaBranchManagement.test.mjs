import test from 'node:test';
import assert from 'node:assert/strict';
import { demoBranches } from '../src/qaBranchDemo.js';
import { canViewSystemAdminSection } from '../src/systemAdminRoleGate.js';

test('branch management is available only to managers and owners in QA', () => {
  for (const role of ['system_owner', 'system_admin', 'employee', 'technical_support', null]) {
    assert.equal(canViewSystemAdminSection(role, 'branches'), false);
    assert.equal(canViewSystemAdminSection(role, 'branches', true), ['system_owner', 'system_admin'].includes(role));
  }
});

test('five distinct branches keep credit, currency and missing counts separate', () => {
  assert.equal(new Set(demoBranches.map(branch => branch.id)).size, 5);
  assert.equal(demoBranches.reduce((total, branch) => total + branch.sales, 0), 400000);
  const [hader, , safira, , atereb] = demoBranches;
  assert.equal(hader.expected, 254000);
  assert.equal(hader.debts.customersSyp, 16000);
  assert.equal(hader.debts.suppliersUsd, 85);
  assert.equal(hader.stockDifferences, 1);
  assert.equal(safira.difference, null);
  assert.equal(safira.stockDifferences, 0);
  assert.equal(atereb.difference, -1000);
});
