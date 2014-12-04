;(function(){

  // Ripped from http://codyhouse.co/gem/vertical-timeline
  jQuery(document).ready(function($){
    var $timeline_block = $('.cd-timeline-block');

    // Hide timeline blocks which are outside the viewport
    $timeline_block.each(function(){
      if($(this).offset().top > $(window).scrollTop()+$(window).height()*0.75) {
        $(this).find('.cd-timeline-img, .cd-timeline-content').addClass('is-hidden');
      }
    });

    // On scolling, show/animate timeline blocks when enter the viewport
    $(window).on('scroll', function(){
      $timeline_block.each(function(){
        if( $(this).offset().top <= $(window).scrollTop()+$(window).height()*0.75 && $(this).find('.cd-timeline-img').hasClass('is-hidden') ) {
          $(this).find('.cd-timeline-img, .cd-timeline-content').removeClass('is-hidden').addClass('bounce-in');
        }
      });
    });
  });
})();