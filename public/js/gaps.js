window.GAPS = function() {
  var GAPS = {};

  function template(name) {
    return $('#_templates>div[data-template="'+name+'"]').children('div').clone();
  };

  GAPS.setupMoveDropdowns = function() {
    $('.move-dropdown input').click(function(e) {
      e.stopPropagation();
    });
    $('.move-dropdown button').click(function(e) {
      $('input', $(this).parent('.move-dropdown')).focus();
    });

    $('.move-dropdown input').keypress(function(e) {
      if(e.which != 13) return true;

      $.ajax({
        type: "POST",
        url: '/ajax/groups/' + $(this).data('group') + '/move',
        data: {
          "category": this.value,
          "_csrf": window.CSRF,
        },
        success: function(data) {
          GAPS.moveGroup(data.group, data.category);
        }
      });
      return false;
    });
  };

  GAPS.newCategory = function(name) {
    var newCat = template('category');
    newCat.attr('id', 'cat-' + name);
    newCat.attr('data-category', name);
    $('h3', newCat).text(name);

    $('#categories').append(newCat);

    return newCat;
  };

  GAPS.moveGroup = function (group, category) {
    var groupElt = $('li[data-group-id="'+ group +'"]');
    var parentCat = groupElt.parents('div.panel');
    var cat = $('div[data-category="'+category+'"]');
    if (cat.length == 0) {
      cat = GAPS.newCategory(category);
    }
    groupElt.appendTo($('ul.list-group', cat));
    if ($('ul>li', parentCat).length == 0) {
      parentCat.remove();
    }
  };

  GAPS.setupEmails = function() {
    $('form.delete-email').submit(function() {
      var form = $(this);
      $.ajax({
        type: 'POST',
        url: form.attr('action'),
        data: form.serialize(),
        success: function() {
          form.parent().remove();
        }
      });
      return false;
    });

    $('form.add-email').submit(function() {
      var form = $(this);
      var email = $('#alternateEmail').val();

      $.ajax({
        type: 'POST',
        url: form.attr('action'),
        data: form.serialize(),
        success: function() {
          $('#alternateEmail').val('');
          var newLi = $('<li class="list-group-item">'+email+'</li>');
          $('#alternate-emails').append(newLi);
        }
      });

      return false;
    });
  };

  GAPS.setupFilters = function() {

    $('.filter-label').blur(function() {
      $('#filter-form').submit();
    });

    $('.filter-archive').change(function() {
      $('#filter-form').submit();
    });

    $('#filter-form').submit(function() {
      var form = $(this);
      // TODO: disable buttons
      $.ajax({
        type: form.attr('method'),
        url: form.attr('action'),
        data: form.serialize(),
        success: function() {
          // TODO: de-disable buttons
        }
      });
      return false;
    });

    // There's a bug where new users don't have filters set. Hacky fix: save on page load for everyone
    $('#filter-form').submit();

    $('#filters-upload').submit(function() {
      return window.confirm('WARNING: this only adds filters to gmail, it does not remove or update them. You likely want to clear all your gmail filters first. Continue?')
    })
  };

  return GAPS;
}();
